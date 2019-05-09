#!/bin/sh

NGINX_CONFIG_FILE=/opt/nginx/conf/nginx.conf


RTMP_CONNECTIONS=${RTMP_CONNECTIONS-1024}
RTMP_STREAM_NAMES=${RTMP_STREAM_NAMES-live,testing}
RTMP_STREAMS=$(echo ${RTMP_STREAM_NAMES} | sed "s/,/\n/g")
RTMP_PUSH_URLS=$(echo ${RTMP_PUSH_URLS} | sed "s/,/\n/g")

apply_config() {

    echo "Creating config"
## Standard config:

cat >${NGINX_CONFIG_FILE} <<!EOF
worker_processes 1;

events {
    worker_connections ${RTMP_CONNECTIONS};
}
!EOF

## HTTP / HLS Config
cat >>${NGINX_CONFIG_FILE} <<!EOF
http {
    include             mime.types;
    default_type        application/octet-stream;
    sendfile            on;
    keepalive_timeout   65;

    server {
        listen          8080;
        server_name     localhost;

        
        location /flv {
            flv_live on; #open flv live streaming (subscribe)
            chunked_transfer_encoding  on; #open 'Transfer-Encoding: chunked' response

            add_header 'Access-Control-Allow-Origin' '*'; #add additional HTTP header
            add_header 'Access-Control-Allow-Credentials' 'true'; #add additional HTTP header
        }

        location /hls {
            types {
                application/vnd.apple.mpegurl m3u8;
                video/mp2t ts;
            }

            root /tmp;
            add_header 'Cache-Control' 'no-cache';
	   
            add_header 'Access-Control-Allow-Origin' '*' always;                
            add_header 'Access-Control-Allow-Credentials' 'true';                
            add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';                
            add_header 'Access-Control-Allow-Headers' 'Range';

        }

        location /on_publish {
            return  201;
        }
        location /stat {
            rtmp_stat all;
            rtmp_stat_stylesheet stat.xsl;
        }
        location /stat.xsl {
            alias /opt/nginx/conf/stat.xsl;
        }
        location /json {
            rtmp_stat all;
            rtmp_stat_format json;
        }
        location /control {
            rtmp_control all;
        }
        
        error_page  500 502 503 504 /50x.html;
        location = /50x.html {
            root html;
        }
    }
}
        
!EOF


## RTMP Config
cat >>${NGINX_CONFIG_FILE} <<!EOF
rtmp {
    out_queue           4096;
    out_cork            8;
    max_streams         128;
    timeout             15s;
    drop_idle_publisher 1800s;
    log_interval 5s; #interval used by log module to log in access.log, it is very useful for debug
    log_size     1m; #buffer size used by log module to log in access.log

    server {
        listen 1935;
        chunk_size 4096;
!EOF

if [ "x${RTMP_PUSH_URLS}" = "x" ]; then
    PUSH="false"
else
    PUSH="true"
fi

HLS="true"

for STREAM_NAME in $(echo ${RTMP_STREAMS}) 
do

echo Creating stream $STREAM_NAME
cat >>${NGINX_CONFIG_FILE} <<!EOF
        application ${STREAM_NAME} {
            live on;
            record off;
            on_publish http://localhost:8080/on_publish;
            gop_cache on;
!EOF
if [ "${HLS}" = "true" ]; then
cat >>${NGINX_CONFIG_FILE} <<!EOF
            hls on;
            hls_path /tmp/hls;
            hls_fragment    1s;
            hls_playlist_length     3s;
!EOF
    HLS="false"
fi
    if [ "$PUSH" = "true" ]; then
        for PUSH_URL in $(echo ${RTMP_PUSH_URLS}); do
            echo "Pushing stream to ${PUSH_URL}"
            cat >>${NGINX_CONFIG_FILE} <<!EOF
            push ${PUSH_URL};
!EOF
            PUSH=false
        done
    fi
cat >>${NGINX_CONFIG_FILE} <<!EOF
        }
!EOF
done

cat >>${NGINX_CONFIG_FILE} <<!EOF
    }
}
!EOF
}

if ! [ -f ${NGINX_CONFIG_FILE} ]; then
    apply_config
else
    echo "CONFIG EXISTS - Not creating!"
fi

echo "Starting server..."
/opt/nginx/sbin/nginx -g "daemon off;"

