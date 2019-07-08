terraform {
 backend "gcs" {
   credentials = "./propro-terraform-admin.json"
   bucket      = "propro-terraform-admin"
   prefix      = "terraform/state"
 }
}
