// Configure the Google Cloud provider
provider "google" {
 credentials = "${file("propro-terraform-admin.json")}"
 project     = "propro-maximo-poc"
 region      = "us-west1"
}

resource "google_container_cluster" "maximo_tf" {
  name     = "maximo-tf"
  location = "us-west1-a"

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count = 1

  # Keep empty empty-pool around to prevent terraform from destroying the
  # cluster everytime we run it. The cluster resource automatically creates
  # an empty pool, which gets mixed up with the first item in node_pool_names.
  #node_pool {
  #  name = "empty-pool"
  #}

  # Explicitly disables basic auth.
  master_auth {
    username = ""
    password = ""

    #client_certificate_config {
    #  issue_client_certificate = false
    #}
  }
}

resource "google_container_node_pool" "maximo_tf_nodes" {
  name       = "maximo-tf-node-pool"
  location   = "${google_container_cluster.maximo_tf.location}"
  cluster    = "${google_container_cluster.maximo_tf.name}"
  node_count = 3
  version = "1.12.8-gke.10"

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    preemptible  = false
    machine_type = "n1-standard-4"

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}

resource "null_resource" "helm_init" {
  provisioner "local-exec" {
    command = "helm init --service-account tiller --wait"
  }

  depends_on = ["google_container_cluster.maximo_tf", "google_container_node_pool.maximo_tf_nodes"]
}

resource "kubernetes_service_account" "tiller" {
  metadata {
    name      = "tiller"
    namespace = "kube-system"
  }

  automount_service_account_token = true
}

resource "kubernetes_cluster_role_binding" "tiller" {
  metadata {
    name = "tiller"
  }

  role_ref {
    kind      = "ClusterRole"
    name      = "cluster-admin"
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind = "ServiceAccount"
    name = "tiller"

    api_group = ""
    namespace = "kube-system"
  }
}


data "helm_repository" "guilledipa" {
    name = "guilledipa"
    url  = "https://guilledipa.github.io/anthos-helm-chart/repo"
}

resource "helm_release" "anthos_cms" {
  name       = "anthos-cms"
  repository = "${data.helm_repository.guilledipa.metadata.0.name}"
  chart      = "anthos-config-management"
  version    = "1.0.0"

  set {
    name  = "git.policyDir"
    value = "k8s"
  }

  set {
    name  = "git.syncRepo"
    value = "https://github.com/guilledipa/ibm-maximo-gke.git"
  }

  set {
    name  = "cluster.name"
    value = "maximo-tf"
  }

  depends_on = ["kubernetes_service_account.tiller", "kubernetes_cluster_role_binding.tiller", "null_resource.helm_init"]
}

resource "kubernetes_service_account" "weblogic-operator-sa" {
  metadata {
    name      = "weblogic-operator-sa"
    namespace = "weblogic-operator"
  }

  automount_service_account_token = true
}

resource "kubernetes_namespace" "maximo" {
  metadata {
    name = "maximo"
  }
}

data "helm_repository" "oracle_github" {
    name = "oracle_github"
    url  = "https://oracle.github.io/weblogic-kubernetes-operator/charts"
}

resource "helm_release" "weblogic_operator" {
  name       = "weblogic-operator"
  namespace  = "weblogic-operator"
  repository = "${data.helm_repository.oracle_github.metadata.0.name}"
  chart      = "weblogic-operator"
  version    = "2.2.1"

  values = [
    "${file("values.yaml")}"
  ]

  depends_on = [
    "kubernetes_service_account.tiller",
    "kubernetes_cluster_role_binding.tiller",
    "null_resource.helm_init",
    "kubernetes_namespace.maximo",
    "kubernetes_service_account.weblogic-operator-sa",
  ]
}

resource "helm_release" "nginx-ingress" {
  name  = "nginx-ingress"
  chart = "stable/nginx-ingress"
}