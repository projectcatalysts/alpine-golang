# Alpine Linux plus Golang
ARG base_image
ARG golang_image
FROM ${golang_image} as golang
FROM ${base_image}

ARG package_version
LABEL package_version="${package_version}"

# copy required files to image
# https://stackoverflow.com/questions/52056387/how-to-install-go-in-alpine-linux
COPY --from=golang /usr/local/go /usr/local/go
COPY ./downloads/known_hosts /root
COPY ./downloads/badger /usr/local/bin

# environment
ENV GOLANG_VERSION ${package_version}
ENV GOROOT /usr/local/go
ENV GOPATH /go
ENV PATH ${GOPATH}/bin:${GOROOT}/bin:$PATH

# do all in one step
RUN apk --no-cache add openssh git zip \
    && mkdir -p /src ~/.ssh/ ${GOPATH}/src ${GOPATH}/bin \
    && cat /root/known_hosts > ~/.ssh/known_hosts \
    && chmod -R 777 $GOPATH \
    && chmod -R 777 /src \
    # cleanup
    && rm /root/known_hosts \
    # final check
    && go version \
    && badger --version
WORKDIR /src