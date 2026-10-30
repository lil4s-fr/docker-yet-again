variable "VERSION" {
  default = "1.0"
}

variable "GIT_SHA" {
  default = "local"
}

variable "REGISTRY" {
  default = "localhost:5000"
}

variable "PLATFORMS" {
  default = ["linux/amd64", "linux/arm64"]
}

group "default" {
  targets = ["api", "worker"]
}

target "_common" {
  platforms = PLATFORMS
  labels = {
    "org.opencontainers.image.version" = VERSION
    "org.opencontainers.image.revision" = GIT_SHA
    "org.opencontainers.image.title" = "shop-sas-stack"
  }
  cache-from = [
    {
      type = "registry"
      ref = "${REGISTRY}/cache:api"
    },
    {
      type = "registry"
      ref = "${REGISTRY}/cache:worker"
    },
  ]
}

target "api" {
  inherits = ["_common"]
  context = "../26-10/tp01-optimisation-image/starter/shopapi"
  dockerfile = "Dockerfile"
  tags = ["${REGISTRY}/shop-api:${VERSION}"]
  args = {
    APP_VERSION = VERSION
    GIT_SHA = GIT_SHA
  }
  cache-to = [
    {
      type = "registry"
      ref = "${REGISTRY}/cache:api"
      mode = "max"
    }
  ]
  output = [
    {
      type = "image"
      push = true
    }
  ]
}

target "worker" {
  inherits = ["_common"]
  context = "../26-10/tp02-buildkit-avance/starter/shop-worker"
  dockerfile = "Dockerfile"
  tags = ["${REGISTRY}/shop-worker:${VERSION}"]
  args = {
    APP_VERSION = VERSION
    GIT_SHA = GIT_SHA
  }
  cache-to = [
    {
      type = "registry"
      ref = "${REGISTRY}/cache:worker"
      mode = "max"
    }
  ]
  output = [
    {
      type = "image"
      push = true
    }
  ]
  secret = [
    {
      type = "file"
      id = "pipconf"
      src = "../26-10/tp02-buildkit-avance/starter/shop-worker/pip.conf"
    }
  ]
}

target "worker-test" {
  inherits = ["_common"]
  context = "../26-10/tp02-buildkit-avance/starter/shop-worker"
  dockerfile = "Dockerfile"
  target = "test"
  cache-to = [
    {
      type = "registry"
      ref = "${REGISTRY}/cache:worker"
      mode = "max"
    }
  ]
  output = [{ type = "cacheonly" }]
  secret = [
    {
      type = "file"
      id = "pipconf"
      src = "../26-10/tp02-buildkit-avance/starter/shop-worker/pip.conf"
    }
  ]
}
