FROM nginx:alpine

LABEL maintainer="Brahim Haouchine"

RUN apk --no-cache add  git \
    && rm -rf /usr/share/nginx/html/* \
    && git clone https://github.com/diranetafen/static-website-example /usr/share/nginx/html/ \
    && rm -rf /usr/share/nginx/html/.git \
    && apk del git


EXPOSE 80


CMD ["nginx", "-g", "daemon off;"]
                                             