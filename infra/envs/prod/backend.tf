terraform {
  backend "s3" {
    bucket       = "docbridge-terraform-state"
    key          = "envs/prod/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}
