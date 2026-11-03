terraform {
  backend "s3" {
    key          = "crewmeister/aws/platform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
