# Basic example: the default, fully private deployment.
#
# APIM's gateway is reachable only through its private endpoint once the
# apply finishes, so apply from, and call the gateway from, a network linked
# to the deployment's VNet (README, "Prerequisites").
#
# Outside this repository, use a pinned Git source instead of the path, for
# example source = "github.com/mbeacom/adrkit-azure?ref=vX.Y.Z", or the
# registry address once the module is published (README, "Publishing to the
# Terraform Registry").

module "adrkit" {
  source = "../.."

  location             = var.location
  name_prefix          = var.name_prefix
  apim_publisher_email = var.apim_publisher_email
  image_tag            = var.image_tag

  repos = [
    { key = "adrkit", url = "https://github.com/mbeacom/adrkit" },
  ]
}
