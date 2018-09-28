########################
# FRONTEND BUILD IMAGE
########################

FROM node:latest AS FRONTEND_BUILDER

ARG MODE

RUN apt-get update -y && apt-get install --no-install-recommends -y \
    build-essential cmake libtool autoconf automake m4 nasm pkg-config libpng-dev nasm \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#make the project dir
ENV APP_HOME=/proj
RUN mkdir -p  $APP_HOME
WORKDIR $APP_HOME

COPY frontend/package.json frontend/package-lock.json $APP_HOME/

#install the dependencies as a separate layer for the sake of caching
RUN npm install

#copy everything else, as we already have the dependencies cached
COPY frontend/. .

#run webpack
RUN npm run $MODE

########################
# BACKEND BUILD IMAGE
########################

FROM openjdk:10-jdk AS BACKEND_BUILDER

ARG AWS_ACCESS_KEY
ARG AWS_SECRET_KEY

#make the project dir
ENV APP_HOME=/proj
RUN mkdir -p  $APP_HOME
WORKDIR $APP_HOME

#copy only the gradle build files first
#the dependencies will be resolved only if they change, otherwise they will be taken from the docker cache
COPY backend/build.gradle backend/settings.gradle backend/gradlew $APP_HOME/
COPY backend/gradle $APP_HOME/gradle
RUN ./gradlew resolveDependencies --continue

#now copy the project itself
#building it will not cause redownloading the dependencies now
COPY backend/. .

COPY --from=FRONTEND_BUILDER /proj/build /proj/src/main/resources/static/
COPY --from=FRONTEND_BUILDER /proj/build/index.html /proj/src/main/resources/templates/

RUN ./gradlew build

########################
# RUNTIME IMAGE
########################

FROM openjdk:10-jre-slim

LABEL vendor="Overseas Labs Limited" \
      vendor.website="http://overseaslsbs.com" \
      description="Web UI" \
      project="Example project" \
      tag="overseaslabs/example-web:1.0.0"

EXPOSE 8080

#copy the distribution from the prev stage and extract it
COPY --from=BACKEND_BUILDER /proj/build/distributions/backend-boot.tar /app/

WORKDIR /app

RUN tar -xvf backend-boot.tar

CMD ["/app/backend-boot/bin/backend"]