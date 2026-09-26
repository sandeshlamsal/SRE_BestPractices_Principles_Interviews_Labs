variable "subscription_id" { type = string }
variable "location" {
  type    = string
  default = "eastus"
}
variable "prefix" {
  type    = string
  default = "sre-lab"
}
variable "kubernetes_version" {
  type    = string
  default = "1.35" # parity with the local kind cluster (v1.35.0)
}
variable "node_vm_size" {
  type = string
  # Standard_D2s_v5 (ADR-0002): DSv5 quota = 0 (P8-ISSUE-1). Standard_B2ms: "not allowed in your subscription in
  # location eastus" (P8-ISSUE-5). Azure's error LISTED the allowed sizes; Dasv7 quota = 10 vCPU.
  # D2as_v7 = AMD, 2 vCPU / 8 GiB, NON-burstable (no CPU-credit cliff), ~$0.09/hr.
  default = "Standard_D2as_v7"
}
variable "node_count" {
  type    = number
  default = 3 # one per availability zone
}
variable "budget_amount" {
  type    = number
  default = 20 # USD / month for the lab resource group
}
variable "budget_contact_emails" { type = list(string) }
variable "zones" {
  type = list(string)
  # [] = no availability zones. On this subscription Standard_B2ms reports NO supported zones in eastus/eastus2
  # ("AvailabilityZoneNotSupported ... supported zones for location 'eastus' are ''"), P8-ISSUE-2.
  # Set ["1","2","3"] once a zone-capable SKU/quota is available.
  default = []
}
