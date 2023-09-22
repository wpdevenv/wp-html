FROM ubuntu:22.04

# script dependencies
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		unzip \
		curl \
		subversion \
	; \
	rm -rf /var/lib/apt/lists/*

WORKDIR /worckspace

COPY install-wp.sh /usr/local/bin/install-wp
RUN chmod +x /usr/local/bin/install-wp

COPY wp-download.sh /usr/local/bin/wp-download
RUN chmod +x /usr/local/bin/wp-download

