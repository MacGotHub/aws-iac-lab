data "aws_vpc" "hub" {
  filter {
    name   = "tag:Name"
    values = ["hub-vpc-w2"]
  }
}

data "aws_subnet" "firewall" {
  filter {
    name   = "tag:Name"
    values = ["hub-firewall-subnet-w2"]
  }
}

data "aws_subnet" "firewall_b" {
  filter {
    name   = "tag:Name"
    values = ["hub-firewall-subnet-w2-b"]
  }
}

resource "aws_networkfirewall_rule_group" "stateless" {
  name     = "lab-stateless-rules-w2"
  type     = "STATELESS"
  capacity = 100

  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        stateless_rule {
          priority = 1
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              protocols = [6]
              source {
                address_definition = "0.0.0.0/0"
              }
              destination {
                address_definition = "0.0.0.0/0"
              }
            }
          }
        }
      }
    }
  }

  tags = {
    Name = "lab-stateless-rules-w2"
  }
}

resource "aws_networkfirewall_rule_group" "stateful" {
  name     = "lab-stateful-rules-w2"
  type     = "STATEFUL"
  capacity = 100

  rule_group {
    rules_source {
      rules_string = <<-EOT
        drop tls $HOME_NET any -> $EXTERNAL_NET 443 (tls.sni; content:"malware.example.com"; nocase; msg:"Block malware domain"; sid:1000001; rev:1;)
        drop http $HOME_NET any -> $EXTERNAL_NET 80 (http.host; content:"malware.example.com"; msg:"Block malware domain HTTP"; sid:1000002; rev:1;)
      EOT
    }
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = {
    Name = "lab-stateful-rules-w2"
  }
}

resource "aws_networkfirewall_firewall_policy" "main" {
  name = "lab-firewall-policy-w2"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateless_rule_group_reference {
      priority     = 1
      resource_arn = aws_networkfirewall_rule_group.stateless.arn
    }

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateful.arn
      priority     = 1
    }

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = {
    Name = "lab-firewall-policy-w2"
  }
}

resource "aws_networkfirewall_firewall" "main" {
  name                = "lab-firewall-w2"
  vpc_id              = data.aws_vpc.hub.id
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main.arn

  subnet_mapping {
    subnet_id = data.aws_subnet.firewall.id
  }

  subnet_mapping {
    subnet_id = data.aws_subnet.firewall_b.id
  }

  tags = {
    Name = "lab-firewall-w2"
  }
}
