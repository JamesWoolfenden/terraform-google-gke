

# ---------------------------------------------------------------------------------------------------------------------
# CREATE A NETWORK TO DEPLOY THE CLUSTER TO
# ---------------------------------------------------------------------------------------------------------------------

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}


# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE KUBECTL AND RBAC ROLE PERMISSIONS
# ---------------------------------------------------------------------------------------------------------------------

# configure kubectl with the credentials of the GKE cluster
resource "null_resource" "configure_kubectl" {
  provisioner "local-exec" {
    command = "gcloud beta container clusters get-credentials ${module.gke_cluster.name} --region ${var.region} --project ${var.project}"

    # Use environment variables to allow custom kubectl config paths
    environment = {
      KUBECONFIG = var.kubectl_config_path != "" ? var.kubectl_config_path : ""
    }
  }

  depends_on = [google_container_node_pool.node_pool]
}

# Create a ServiceAccount for Tiller
resource "kubernetes_service_account" "tiller" {
  metadata {
    name      = "tiller"
    namespace = local.tiller_namespace
  }
}

resource "kubernetes_cluster_role_binding" "user" {
  metadata {
    name = "admin-user"
  }

  role_ref {
    kind      = "ClusterRole"
    name      = "cluster-admin"
    api_group = "rbac.authorization.k8s.io"
  }

  subject {
    kind      = "User"
    name      = data.google_client_openid_userinfo.terraform_user.email
    api_group = "rbac.authorization.k8s.io"
  }

  # We give the Tiller ServiceAccount cluster admin status so that we can deploy anything in any namespace using this
  # Tiller instance for testing purposes. In production, you might want to use a more restricted role.
  subject {
    # this is a workaround for https://github.com/terraform-providers/terraform-provider-kubernetes/issues/204.
    # we have to set an empty api_group or the k8s call will fail. It will be fixed in v1.5.2 of the k8s provider.
    api_group = ""

    kind      = "ServiceAccount"
    name      = kubernetes_service_account.tiller.metadata[0].name
    namespace = local.tiller_namespace
  }

  subject {
    kind      = "Group"
    name      = "system:masters"
    api_group = "rbac.authorization.k8s.io"
  }
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# GENERATE TLS CERTIFICATES FOR USE WITH TILLER
# This will use kubergrunt to generate TLS certificates, and upload them as Kubernetes Secrets that can then be used by
# Tiller.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

resource "null_resource" "tiller_tls_certs" {
  provisioner "local-exec" {
    command = <<-EOF
      kubergrunt tls gen --ca --namespace kube-system --secret-name ${local.tls_ca_secret_name} --secret-label gruntwork.io/tiller-namespace=${local.tiller_namespace} --secret-label gruntwork.io/tiller-credentials=true --secret-label gruntwork.io/tiller-credentials-type=ca --tls-subject-json '${jsonencode(var.tls_subject)}' ${local.tls_algorithm_config} ${local.kubectl_auth_config}

      kubergrunt tls gen --namespace ${local.tiller_namespace} --ca-secret-name ${local.tls_ca_secret_name} --ca-namespace kube-system --secret-name ${local.tls_secret_name} --secret-label gruntwork.io/tiller-namespace=${local.tiller_namespace} --secret-label gruntwork.io/tiller-credentials=true --secret-label gruntwork.io/tiller-credentials-type=server --tls-subject-json '${jsonencode(var.tls_subject)}' ${local.tls_algorithm_config} ${local.kubectl_auth_config}
    EOF

    # Use environment variables for Kubernetes credentials to avoid leaking into the logs
    environment = {
      KUBECTL_SERVER_ENDPOINT = data.template_file.gke_host_endpoint.rendered
      KUBECTL_CA_DATA         = base64encode(data.template_file.cluster_ca_certificate.rendered)
      KUBECTL_TOKEN           = data.template_file.access_token.rendered
    }
  }
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# CONFIGURE OPERATOR HELM CLIENT
# To allow usage of the helm client immediately, we grant access to the admin RBAC user and configure the local helm
# client.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

resource "null_resource" "grant_and_configure_helm" {
  provisioner "local-exec" {
    command = <<-EOF
    kubergrunt helm grant --tiller-namespace ${local.tiller_namespace} --tls-subject-json '${jsonencode(var.client_tls_subject)}' --rbac-user ${data.google_client_openid_userinfo.terraform_user.email} ${local.kubectl_auth_config}

    kubergrunt helm configure --helm-home ${pathexpand("~/.helm")} --tiller-namespace ${local.tiller_namespace} --resource-namespace ${local.resource_namespace} --rbac-user ${data.google_client_openid_userinfo.terraform_user.email} ${local.kubectl_auth_config}
    EOF

    # Use environment variables for Kubernetes credentials to avoid leaking into the logs
    environment = {
      KUBECTL_SERVER_ENDPOINT = data.template_file.gke_host_endpoint.rendered
      KUBECTL_CA_DATA         = base64encode(data.template_file.cluster_ca_certificate.rendered)
      KUBECTL_TOKEN           = data.template_file.access_token.rendered
    }
  }

  depends_on = [null_resource.wait_for_tiller]
}

