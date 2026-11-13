
terraform {
  backend "s3" {
    bucket  = "pgr301-terraform-state"
    key     = "wishifai/21/terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
  }
}
