variable "subscription_id" {
  type        = string
  description = "Subscription to deploy the example into."
}

variable "location" {
  type        = string
  description = "Azure region to deploy the example into."
  default     = "eastus"
}

variable "network_resource_group_name" {
  type        = string
  description = "Resource group holding the existing virtual network and private DNS zones."
}

variable "virtual_network_name" {
  type        = string
  description = "Existing virtual network containing the private endpoint subnet."
}

variable "subnet_name" {
  type        = string
  description = "Existing subnet to place the private endpoint in."
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics workspace to send diagnostics to."
}

variable "entra_admin_login" {
  type        = string
  description = "Display name or user principal name of the server's Entra ID administrator (preferably a group)."
}

variable "entra_admin_object_id" {
  type        = string
  description = "Object ID of the server's Entra ID administrator."
}
