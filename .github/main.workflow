workflow "Build and Publish" {
  on = "push"
  resolves = [
    "Docker Login"
  ]
}

action "Shell Lint" {
  uses = "actions/bin/shellcheck@master"
  args = ".github/actions/nix-build/entrypoint.sh .github/actions/skopeo/entrypoint.sh"
}

action "Docker Lint" {
  uses = "docker://replicated/dockerfilelint"
  args = [ ".github/actions/nix-build/Dockerfile", ".github/actions/skopeo/Dockerfile" ]
}

action "Build Docker Image (FDB-6.1)" {
  uses = "./.github/actions/nix-build"
  needs = [ "Shell Lint", "Docker Lint" ]
  args = "foundationdb61"
}

action "Docker Login" {
  uses = "actions/docker/login@master"
  secrets = [ "DOCKER_USERNAME", "DOCKER_PASSWORD" ]
  needs = [
    "Build Docker Image (FDB-6.1)"
  ]
}
