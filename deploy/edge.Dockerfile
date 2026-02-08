FROM ghcr.io/cirruslabs/flutter:stable AS web-build

ARG API_BASE_URL

WORKDIR /workspace/app

COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter config --enable-web && flutter pub get

COPY app ./
RUN flutter build web --release --dart-define=BRUSHLOOP_API_BASE_URL=${API_BASE_URL}

FROM caddy:2.8-alpine

COPY deploy/Caddyfile /etc/caddy/Caddyfile
COPY --from=web-build /workspace/app/build/web /srv/flutter-web
