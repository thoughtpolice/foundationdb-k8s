FROM lnl7/nix:2.2.2

LABEL name="Skopeo Copy for GitHub Actions"
LABEL version="1.0"
LABEL repository="http://github.com/thoughtpolice/foundationdb-k8s"
LABEL homepage="http://github.com/thoughtpolice/foundationdb-k8s"
LABEL maintainer="Austin Seipp <aseipp@pobox.com>"

LABEL "com.github.actions.name"="Skopeo Copy"
LABEL "com.github.actions.description"="Push a Docker Archive into a Container Registry"
LABEL "com.github.actions.icon"="cloud"
LABEL "com.github.actions.color"="red"

RUN nix-env -iA nixpkgs.gnutar nixpkgs.gzip && nix-env -iA skopeo bash coreutils git -f https://github.com/NixOS/nixpkgs-channels/archive/190727db4ea7e0d083e7dbcb66ced11f31b340f0.tar.gz

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "--help" ]
