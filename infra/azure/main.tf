locals {
  tags = { project = "sre-lab", owner = "sandesh", managed_by = "terraform", phase = "8" }
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = local.tags
}

# GUARDRAIL FIRST: budget alerts on the lab resource group (actual 50/80/100%, forecast 100%).
resource "azurerm_consumption_budget_resource_group" "lab" {
  name              = "${var.prefix}-budget"
  resource_group_id = azurerm_resource_group.lab.id
  amount            = var.budget_amount
  time_grain        = "Monthly"
  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }
  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      enabled        = true
      threshold      = notification.value
      operator       = "GreaterThanOrEqualTo"
      threshold_type = "Actual"
      contact_emails = var.budget_contact_emails
    }
  }
  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Forecasted"
    contact_emails = var.budget_contact_emails
  }
  lifecycle { ignore_changes = [time_period] } # timestamp() would otherwise diff on every plan
}

resource "azurerm_kubernetes_cluster" "lab" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  dns_prefix          = var.prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free" # no control-plane charge (no uptime SLA): fine for a lab
  tags                = local.tags

  default_node_pool {
    name                         = "system"
    vm_size                      = var.node_vm_size
    node_count                   = var.node_count
    zones                        = var.zones # see variables.tf: no zone support for B2ms on this subscription
    os_disk_size_gb              = 30        # the 128 GB Premium default costs ~4x (ADR-0002)
    os_disk_type                 = "Managed"
    only_critical_addons_enabled = false
    upgrade_settings { max_surge = "1" }
  }

  identity { type = "SystemAssigned" }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium" # Azure CNI powered by Cilium: enforces NetworkPolicy (tool-stack.md)
    load_balancer_sku   = "standard"
  }

  # No Container Insights / Log Analytics: ~$2.30/GB ingestion; telemetry goes to our own stack (ADR-0002).
}
