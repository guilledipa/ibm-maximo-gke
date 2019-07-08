provider "kubernetes" {
  config_context_cluster   = "gke_propro-maximo-poc_us-west1-a_maximo-tf"
}

provider "helm" {
    service_account = "tiller"
    namespace = "kube-system"
    install_tiller = true
    debug = true
    insecure = true
    // kubernetes {}
}