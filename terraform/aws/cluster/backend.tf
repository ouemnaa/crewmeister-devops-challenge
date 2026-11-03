terraform {
  backend "s3" {
    key          = "crewmeister/aws/cluster.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
