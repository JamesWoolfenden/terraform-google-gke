# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY TILLER TO THE GKE CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

module "tiller" {
  source = "github.com/gruntwork-io/terraform-kubernetes-helm.git//modules/k8s-tiller?ref=v0.5.0"

  tiller_tls_gen_method                    = "none"
  tiller_service_account_name              = kubernetes_service_account.tiller.metadata[0].name
  tiller_service_account_token_secret_name = kubernetes_service_account.tiller.default_secret_name
  tiller_tls_secret_name                   = local.tls_secret_name
  namespace                                = local.tiller_namespace
  tiller_image_version                     = local.tiller_version

  # Kubergrunt will store the private key under the key "tls.pem" in the corresponding Secret resource, which will be
  # accessed as a file when mounted into the container.
  tiller_tls_key_file_name = "tls.pem"

  dependencies = [null_resource.tiller_tls_certs.id, kubernetes_cluster_role_binding.user.id]
}

# The Deployment resources created in the module call to `k8s-tiller` will be complete creation before the rollout is
# complete. We use kubergrunt here to wait for the deployment to complete, so that when this resource is done creating,
# any resources that depend on this can assume Tiller is successfully deployed and up at that point.
resource "null_resource" "wait_for_tiller" {
  provisioner "local-exec" {
    command = "kubergrunt helm wait-for-tiller --tiller-namespace ${local.tiller_namespace} --tiller-deployment-name ${module.tiller.deployment_name} --expected-tiller-version ${local.tiller_version} ${local.kubectl_auth_config}"

    # Use environment variables for Kubernetes credentials to avoid leaking into the logs
    environment = {
      KUBECTL_SERVER_ENDPOINT = data.template_file.gke_host_endpoint.rendered
      KUBECTL_CA_DATA         = base64encode(data.template_file.cluster_ca_certificate.rendered)
      KUBECTL_TOKEN           = data.template_file.access_token.rendered
    }
  }
}
