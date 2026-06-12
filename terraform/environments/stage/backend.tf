terraform {
  cloud {
    organization = "circleguard"
    workspaces {
      name = "circleguard-stage"
    }
  }
}
