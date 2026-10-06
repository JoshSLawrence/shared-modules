variable "subscription_id" {
  type        = string
  description = "Subscription to deploy the example into."
}

variable "location" {
  type        = string
  description = "Azure region to deploy the example into."
  default     = "eastus"
}

variable "synapse_admin_group_object_id" {
  type        = string
  description = "Object ID of the Entra ID group to make Synapse Administrator."
}
