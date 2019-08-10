# ---------------------------------------------------------------------------------------------------------------------
# COMPUTATIONS
# These locals set constants and compute various useful information used throughout this Terraform module.
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # For this example, we hardcode our tiller namespace to kube-system. In production, you might want to consider using a
  # different Namespace.
  tiller_namespace = "kube-system"

  # For this example, we setup Tiller to manage the default Namespace.
  resource_namespace = "default"

  # We install an older version of Tiller to match the Helm library version used in the Terraform helm provider.
  tiller_version = "v2.11.0"

  # We store the CA Secret in the kube-system Namespace, given that only cluster admins should access these.
  tls_ca_secret_namespace = "kube-system"

  # We name the TLS Secrets to be compatible with the `kubergrunt helm grant` command
  tls_ca_secret_name   = "${local.tiller_namespace}-namespace-tiller-ca-certs"
  tls_secret_name      = "tiller-certs"
  tls_algorithm_config = "--tls-private-key-algorithm ${var.private_key_algorithm} ${var.private_key_algorithm == "ECDSA" ? "--tls-private-key-ecdsa-curve ${var.private_key_ecdsa_curve}" : "--tls-private-key-rsa-bits ${var.private_key_rsa_bits}"}"

  # These will be filled in by the shell environment
  kubectl_auth_config = "--kubectl-server-endpoint \"$KUBECTL_SERVER_ENDPOINT\" --kubectl-certificate-authority \"$KUBECTL_CA_DATA\" --kubectl-token \"$KUBECTL_TOKEN\""
}

