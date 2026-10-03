# Build from the repository root:
#   docker build -f apps/server/Dockerfile -t bombario-server .
#   docker run -p 8080:8080 bombario-server
FROM dart:stable AS build
WORKDIR /src
COPY packages/bombario_core packages/bombario_core
COPY packages/bombario_net packages/bombario_net
COPY apps/server apps/server
WORKDIR /src/apps/server
RUN mkdir -p /out && dart pub get && dart compile exe bin/server.dart -o /out/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server
ENV PORT=8080
EXPOSE 8080
CMD ["/app/server"]
