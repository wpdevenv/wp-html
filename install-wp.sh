#!/usr/bin/env bash

WP_VERSION="${WP_VERSION:-latest}"

DB_HOST="${DB_HOST:-db\:3306}"
DB_NAME="${DB_NAME:-develop}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-wordpress}"
DB_PREFIX="${DB_PREFIX:-wp_}"

WP_EXTRA_CONFIG="${WP_EXTRA_CONFIG:-\\
define( 'SCRIPT_DEBUG', true );\\
define( 'AUTOMATIC_UPDATER_DISABLED', true );\\
define( 'FS_METHOD', 'direct' );\\
}"
WP_CORE_DIR="${INSTALL_DIR:-html}"

WP_TESTS_DIR="${WP_CORE_DIR}/tests"
DB_TEST_NAME="${DB_TEST_NAME:-wp_test}"

TMPDIR="${TMPDIR:-/tmp}"
TMPDIR=$(echo $TMPDIR | sed -e "s/\/$//")

download() {
    if [ `which curl` ]; then
        curl -s "$1" > "$2";
    elif [ `which wget` ]; then
        wget -nv -O "$2" "$1"
    fi
}

if [ ! -d $WP_CORE_DIR ]; then
	mkdir -p $WP_CORE_DIR
fi

if [[ $WP_VERSION =~ ^[0-9]+\.[0-9]+\-(beta|RC)[0-9]+$ ]]; then
	WP_BRANCH=${WP_VERSION%\-*}
	WP_TESTS_TAG="branches/$WP_BRANCH"

elif [[ $WP_VERSION =~ ^[0-9]+\.[0-9]+$ ]]; then
	WP_TESTS_TAG="branches/$WP_VERSION"
elif [[ $WP_VERSION =~ [0-9]+\.[0-9]+\.[0-9]+ ]]; then
	if [[ $WP_VERSION =~ [0-9]+\.[0-9]+\.[0] ]]; then
		# version x.x.0 means the first release of the major version, so strip off the .0 and download version x.x
		WP_TESTS_TAG="tags/${WP_VERSION%??}"
	else
		WP_TESTS_TAG="tags/$WP_VERSION"
	fi
elif [[ $WP_VERSION == 'nightly' || $WP_VERSION == 'trunk' ]]; then
	WP_TESTS_TAG="trunk"
else
	# http serves a single offer, whereas https serves multiple. we only want one
	download http://api.wordpress.org/core/version-check/1.7/ $TMPDIR/wp-latest.json
	grep '[0-9]+\.[0-9]+(\.[0-9]+)?' $TMPDIR/wp-latest.json
	LATEST_VERSION=$(grep -o '"version":"[^"]*' $TMPDIR/wp-latest.json | sed 's/"version":"//')
	if [[ -z "$LATEST_VERSION" ]]; then
		echo "Latest WordPress version could not be found"
		exit 1
	fi
	WP_TESTS_TAG="tags/$LATEST_VERSION"
fi
set -ex

install_wp() {

	if [[ $WP_VERSION == 'nightly' || $WP_VERSION == 'trunk' ]]; then
		mkdir -p $TMPDIR/wordpress-trunk
		rm -rf $TMPDIR/wordpress-trunk/*
		svn export --quiet https://core.svn.wordpress.org/trunk $TMPDIR/wordpress-trunk/wordpress
		mv $TMPDIR/wordpress-trunk/wordpress/* $WP_CORE_DIR
	else
		if [ $WP_VERSION == 'latest' ]; then
			local ARCHIVE_NAME='latest'
		elif [[ $WP_VERSION =~ [0-9]+\.[0-9]+ ]]; then
			# https serves multiple offers, whereas http serves single.
			download https://api.wordpress.org/core/version-check/1.7/ $TMPDIR/wp-latest.json
			if [[ $WP_VERSION =~ [0-9]+\.[0-9]+\.[0] ]]; then
				# version x.x.0 means the first release of the major version, so strip off the .0 and download version x.x
				LATEST_VERSION=${WP_VERSION%??}
			else
				# otherwise, scan the releases and get the most up to date minor version of the major release
				local VERSION_ESCAPED=`echo $WP_VERSION | sed 's/\./\\\\./g'`
				LATEST_VERSION=$(grep -o '"version":"'$VERSION_ESCAPED'[^"]*' $TMPDIR/wp-latest.json | sed 's/"version":"//' | head -1)
			fi
			if [[ -z "$LATEST_VERSION" ]]; then
				local ARCHIVE_NAME="wordpress-$WP_VERSION"
			else
				local ARCHIVE_NAME="wordpress-$LATEST_VERSION"
			fi
		else
			local ARCHIVE_NAME="wordpress-$WP_VERSION"
		fi
		download https://wordpress.org/${ARCHIVE_NAME}.tar.gz  $TMPDIR/wordpress.tar.gz
		tar --strip-components=1 -zxmf $TMPDIR/wordpress.tar.gz -C $WP_CORE_DIR

	fi
 	if ! [ -d $WP_CORE_DIR/wp-content/uploads ]; then
		mkdir $WP_CORE_DIR/wp-content/uploads
  	fi
}

install_config() {
	if [ ! -e "$WP_CORE_DIR/.htaccess" ]; then
		{ \
			echo '# BEGIN WordPress'; \
			echo ''; \
			echo 'RewriteEngine On'; \
			echo 'RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]'; \
			echo 'RewriteBase /'; \
			echo 'RewriteRule ^index\.php$ - [L]'; \
			echo 'RewriteCond %{REQUEST_FILENAME} !-f'; \
			echo 'RewriteCond %{REQUEST_FILENAME} !-d'; \
			echo 'RewriteRule . /index.php [L]'; \
			echo ''; \
			echo '# END WordPress'; \
		} > $WP_CORE_DIR/.htaccess; 
	fi;

	if [ ! -f "$WP_CORE_DIR"/wp-config.php ]; then
		download https://develop.svn.wordpress.org/${WP_TESTS_TAG}/wp-config-sample.php "$WP_CORE_DIR"/wp-config.php
		# remove all forward slashes in the end
		WP_CORE_DIR=$(echo $WP_CORE_DIR | sed "s:/\+$::")	
		sed -i "s/database_name_here/$DB_NAME/" "$WP_CORE_DIR"/wp-config.php
		sed -i "s/username_here/$DB_USER/" "$WP_CORE_DIR"/wp-config.php
		sed -i "s/password_here/$DB_PASS/" "$WP_CORE_DIR"/wp-config.php
		sed -i "s|localhost|${DB_HOST}|" "$WP_CORE_DIR"/wp-config.php
		sed -i "s|'wp_'|'${DB_PREFIX}'|" "$WP_CORE_DIR"/wp-config.php
		sed -i "s|define( 'WP_DEBUG', false );|define( 'WP_DEBUG', true );|" "$WP_CORE_DIR"/wp-config.php
		sed -i "s|\"stop editing\" line. \*\/|\"stop editing\" line. \*\/\n${WP_EXTRA_CONFIG}|" "$WP_CORE_DIR"/wp-config.php
	fi
}

install_test_suite() {
	# portable in-place argument for both GNU sed and Mac OSX sed
	if [[ $(uname -s) == 'Darwin' ]]; then
		local ioption='-i.bak'
	else
		local ioption='-i'
	fi

	# set up testing suite if it doesn't yet exist
	if [ ! -d $WP_TESTS_DIR ]; then
		# set up testing suite
		mkdir -p $WP_TESTS_DIR
		rm -rf $WP_TESTS_DIR/{includes,data}
		svn export --quiet --ignore-externals https://develop.svn.wordpress.org/${WP_TESTS_TAG}/tests/phpunit/includes/ $WP_TESTS_DIR/includes
		svn export --quiet --ignore-externals https://develop.svn.wordpress.org/${WP_TESTS_TAG}/tests/phpunit/data/ $WP_TESTS_DIR/data
	fi

	# if [ ! -f "$WP_TESTS_DIR"/wp-tests-config.php ]; then
		download https://develop.svn.wordpress.org/${WP_TESTS_TAG}/wp-tests-config-sample.php "$WP_TESTS_DIR"/wp-tests-config.php
		# remove all forward slashes in the end
		WP_TESTS_DIR=$(echo $WP_TESTS_DIR | sed "s:/\+$::")
		sed $ioption "s:dirname( __FILE__ ) . '/src/':dirname( dirname( __FILE__ ) ) . '/':" "$WP_TESTS_DIR"/wp-tests-config.php
		sed $ioption "s:__DIR__ . '/src/':dirname( dirname( __FILE__ ) ) . '/':" "$WP_TESTS_DIR"/wp-tests-config.php
		sed $ioption "s/youremptytestdbnamehere/$DB_TEST_NAME/" "$WP_TESTS_DIR"/wp-tests-config.php
		sed $ioption "s/yourusernamehere/$DB_USER/" "$WP_TESTS_DIR"/wp-tests-config.php
		sed $ioption "s/yourpasswordhere/$DB_PASS/" "$WP_TESTS_DIR"/wp-tests-config.php
		sed $ioption "s|localhost|${DB_HOST}|" "$WP_TESTS_DIR"/wp-tests-config.php
	# fi

}

install_wp
install_config
install_test_suite

rm -rf $TMPDIR/*
