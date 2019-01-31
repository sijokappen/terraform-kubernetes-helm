# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# DEPLOY TILLER, GRANT ACCESS, AND CONFIGURE LOCAL HELM CLIENT
# These templates user kubergrunt to deploy a new Tiller instance, while granting access to the specified RBAC entities.
# Optionally configure the local helm client.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# ---------------------------------------------------------------------------------------------------------------------
# SET TERRAFORM REQUIREMENTS FOR RUNNING THIS MODULE
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  required_version = "~> 0.9"
}

# ---------------------------------------------------------------------------------------------------------------------
# SET MODULE DEPENDENCY RESOURCE
# This works around a terraform limitation where we can not specify module dependencies natively.
# See https://github.com/hashicorp/terraform/issues/1178 for more discussion.
# ---------------------------------------------------------------------------------------------------------------------

resource "null_resource" "dependency_getter" {
  provisioner "local-exec" {
    command = "echo ${length(var.dependencies)}"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY TILLER
# ---------------------------------------------------------------------------------------------------------------------

resource "null_resource" "tiller" {
  triggers {
    tiller_namespace = "${var.tiller_namespace}"
  }

  provisioner "local-exec" {
    command = "kubergrunt helm deploy ${local.kubectl_config_options} --service-account ${var.service_account} --tiller-namespace ${var.tiller_namespace} ${local.tls_config}"
  }

  provisioner "local-exec" {
    command = "kubergrunt helm undeploy ${local.kubectl_config_options} --home ${local.helm_home_with_default} --tiller-namespace ${var.tiller_namespace} ${local.undeploy_args}"
    when    = "destroy"
  }

  depends_on = ["null_resource.dependency_getter"]
}

# ---------------------------------------------------------------------------------------------------------------------
# GRANT ACCESS TO TILLER TO THE SPECIFIED RBAC ENTITIES
# ---------------------------------------------------------------------------------------------------------------------

resource "null_resource" "grant_access_to_tiller" {
  count = "${trimspace(local.grant_args) == "" ? 0 : 1}"

  triggers {
    grant_args = "${local.grant_args}"
  }

  provisioner "local-exec" {
    command = "kubergrunt helm grant ${local.kubectl_config_options} --tiller-namespace ${var.tiller_namespace} ${local.tls_config} ${local.grant_args}"
  }

  depends_on = ["null_resource.tiller", "null_resource.dependency_getter"]
}

# ---------------------------------------------------------------------------------------------------------------------
# CONFIGURE THE LOCAL HELM CLIENT
# ---------------------------------------------------------------------------------------------------------------------

resource "null_resource" "configure_local_helm_client" {
  count = "${trimspace(local.configure_args) == "" ? 0 : 1}"

  triggers {
    configure_args = "${local.configure_args}"
  }

  provisioner "local-exec" {
    command = "kubergrunt helm configure ${local.kubectl_config_options} --home ${local.helm_home_with_default} --tiller-namespace ${var.tiller_namespace} --resource-namespace ${var.resource_namespace} --set-kubectl-namespace ${local.configure_args}"
  }

  depends_on = ["null_resource.grant_access_to_tiller", "null_resource.dependency_getter"]
}

# ---------------------------------------------------------------------------------------------------------------------
# SET MODULE CHILD DEPENDENCY RESOURCE
# This works around a terraform limitation where we can not specify module dependencies natively.
# See https://github.com/hashicorp/terraform/issues/1178 for more discussion.
# ---------------------------------------------------------------------------------------------------------------------

# List resource(s) that will be constructed last within the module, so that we can create an output that can be used to
# chain dependencies.
resource "null_resource" "dependency_setter" {
  depends_on = [
    "null_resource.tiller",
    "null_resource.grant_access_to_tiller",
    "null_resource.configure_local_helm_client",
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# INTERPOLATE AND CONSTRUCT COMMAND ARGUMENTS
# ---------------------------------------------------------------------------------------------------------------------

// TODO: When we have package-terraform-utilities available
// - Implement multiline shell commands by selecting the escape character based on platform (\ for unix, ^ for windows)
// - Implement command required

locals {
  helm_home_with_default = "${var.helm_home == "" ? pathexpand("~/.helm") : var.helm_home}"
  kubectl_config_options = "${var.kubectl_config_context_name != "" ? "--kubectl-context-name ${var.kubectl_config_context_name}" : ""} ${var.kubectl_config_path != "" ? "--kubeconfig ${var.kubectl_config_path}" : ""}"

  tls_config           = "--tls-private-key-algorithm ${var.private_key_algorithm} ${local.tls_algorithm_config} --tls-common-name ${lookup(var.tls_subject, "common_name")} --tls-org ${lookup(var.tls_subject, "org")} ${local.tls_org_unit} ${local.tls_city} ${local.tls_state} ${local.tls_country}"
  tls_algorithm_config = "${var.private_key_algorithm == "ECDSA" ? "--tls-private-key-ecdsa-curve ${var.private_key_ecdsa_curve}" : "--tls-private-key-rsa-bits ${var.private_key_rsa_bits}"}"
  tls_org_unit         = "${lookup(var.tls_subject, "org_unit", "") != "" ? "--tls-org-unit ${lookup(var.tls_subject, "org_unit", "")}" : ""}"
  tls_city             = "${lookup(var.tls_subject, "city", "")     != "" ? "--tls-city ${lookup(var.tls_subject, "city", "")}"         : ""}"
  tls_state            = "${lookup(var.tls_subject, "state", "")    != "" ? "--tls-state ${lookup(var.tls_subject, "state", "")}"       : ""}"
  tls_country          = "${lookup(var.tls_subject, "country", "")  != "" ? "--tls-country ${lookup(var.tls_subject, "country", "")}"   : ""}"

  undeploy_args = "${var.force_undeploy ? "--force" : ""} ${var.undeploy_releases ? "--undeploy-releases" : ""}"

  grant_args                 = "${local.rbac_users_args} ${local.rbac_groups_args} ${local.rbac_service_accounts_args}"
  rbac_users_args            = "${join(" ", formatlist("--rbac-user %s", var.grant_access_to_rbac_users))}"
  rbac_groups_args           = "${join(" ", formatlist("--rbac-group %s", var.grant_access_to_rbac_groups))}"
  rbac_service_accounts_args = "${join(" ", formatlist("--rbac-service-account %s", var.grant_access_to_rbac_service_accounts))}"

  configure_args = "${
    var.helm_client_rbac_user != "" ? "--rbac-user ${var.helm_client_rbac_user}" 
      : var.helm_client_rbac_group != "" ? "--rbac-group ${var.helm_client_rbac_group}"
        : var.helm_client_rbac_service_account != "" ? "--rbac-service-account ${var.helm_client_rbac_service_account}"
          : ""
  }"
}