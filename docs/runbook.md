# Runbook — exact commands to work on this repo

This is the literal command sequence for deploying, verifying, and tearing
down the labs. It assumes nothing beyond a shell with `tofu` and `aws`
installed. For what the architecture *is*, see `docs/architecture.md` (v1,
labs 02-10) and `opentofu/lab-01-vpc/DESIGN.md` (v2 rebuild).

---

## 0. Prerequisites (every session)

### 0.1 AWS credentials

Every `tofu` command below talks to AWS account `351668480009`. If your
session has expired you will see errors like `ExpiredToken`,
`InvalidClientTokenId`, or `no valid credential sources`. Re-authenticate
first (e.g. `aws login`, or however your local AWS credentials are
configured), then confirm you are in the right account:

```bash
aws sts get-caller-identity
# "Account" must be 351668480009. If it isn't, STOP — you are pointed at the wrong account.
```

### 0.2 Remote state backend must already exist

All labs store state in S3 with DynamoDB locking. `tofu init` fails if these
don't exist. They were bootstrapped manually (not managed by any lab's code):

| Resource | Name | Region |
|---|---|---|
| S3 bucket | `351668480009-opentofu-state` | us-east-1 |
| DynamoDB table | `opentofu-state-lock` | us-east-1 |

Verify they exist:

```bash
aws s3api head-bucket --bucket 351668480009-opentofu-state
aws dynamodb describe-table --table-name opentofu-state-lock --region us-east-1 --query 'Table.TableStatus'
```

If either is missing (e.g. fresh account), recreate them before any `tofu init`:

```bash
aws s3api create-bucket --bucket 351668480009-opentofu-state --region us-east-1
aws dynamodb create-table \
  --table-name opentofu-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Each lab's `backend.tf` names its own state key (e.g. lab-01-vpc uses
`hub-vpc/terraform.tfstate`); the full key list is in `docs/architecture.md`.

---

## 1. The universal per-lab command sequence

Every lab directory is an independent OpenTofu root module. The sequence is
always the same:

```bash
cd opentofu/<lab-dir>       # e.g. opentofu/lab-01-vpc
tofu init                   # first time in this dir, or after backend/provider changes
tofu validate               # syntax/reference check, no AWS calls
tofu plan                   # READ THE OUTPUT — see rules below
tofu apply                  # prompts for confirmation; review the plan again before typing "yes"
```

Rules for reading `tofu plan` output before ever applying:

- Building something new: expect only `+ create` lines. Any `- destroy` or
  `-/+ replace` line means the plan touches existing infrastructure — stop and
  understand why before applying.
- `tofu plan` with **no changes** means code and deployed state already match.
- If plan errors with credential messages, go back to step 0.1. If it errors
  about the backend/lock table, go back to step 0.2.
- If a run dies and leaves a stale lock ("Error acquiring the state lock"),
  confirm no other apply is running, then `tofu force-unlock <lock-id>`.

Useful checks at any time:

```bash
tofu state list    # what this lab currently manages in AWS
tofu output        # this lab's exported values
```

---

## 2. v1 labs (02-10): order and commands

Dependency order and teardown order are documented in `docs/architecture.md`
("Deployment Order" / "Teardown Order"). To deploy the full v1 stack manually,
run the section-1 sequence in each directory **in this order**:

```
lab-02-vpn → lab-03-vpc → lab-04-firewall → lab-05-tgw → lab-06-ec2
→ lab-07-vpc-w2 → lab-08-firewall-w2 → lab-09-tgw-w2 → lab-10-ec2-w2
```

(Historically the chain started with the v1 lab-01-vpc hub; that directory has
since been rebuilt to the v2 design — see section 3. Labs 04 and 05 depend on
the old v1 hub VPC, so a full v1 redeploy is no longer possible without
checking section 3 first.)

Convenience scripts at repo root (`apply-all.sh`, `destroy-all.sh`) loop
`tofu apply -auto-approve` / `tofu destroy -auto-approve` over all ten labs
including lab-01-vpc. They assume every lab is already `tofu init`-ed, and
`-auto-approve` skips plan review — prefer the manual per-lab sequence unless
you are confident. **Note:** these scripts still include `lab-01-vpc` from the
v1 era; running them will apply/destroy the in-progress v2 code in that
directory.

Manual step unique to v1: firewall endpoint IDs change on every
destroy/apply. After re-applying lab-04-firewall (or lab-08-firewall-w2), copy
the new `vpce-*` IDs from `tofu output` into the `locals` block of
`lab-05-tgw/main.tf` (or `lab-09-tgw-w2/main.tf`) before applying the TGW lab.
Details in `docs/architecture.md`, "Important: After Destroy/Redeploy".

Cost warning: the full v1 stack costs roughly $2/hr while deployed (firewall
endpoints dominate). Tear down when not actively testing.

---

## 3. lab-01-vpc (v2 rebuild): how to build and apply

### 3.1 Before your first apply — one-time safety check

The rebuilt lab-01-vpc reuses the v1 state key `hub-vpc/terraform.tfstate`
(see `opentofu/lab-01-vpc/backend.tf`). Consequences:

- If the **old v1 hub VPC is still deployed**, the first plan will show the
  old hub resources being destroyed/replaced (the hub CIDR changed from
  10.0.0.0/16 to 10.0.0.0/20, which forces VPC replacement). v1 labs 04 and
  05 were built on that old hub — if they are deployed, destroy them first
  (teardown order in `docs/architecture.md`) or the apply will break them.
- If **nothing is deployed** (state empty or already migrated), the plan
  should show only `+ create` lines.

Check before deciding: `tofu state list` in `opentofu/lab-01-vpc/`.

### 3.2 Iterative build loop

OpenTofu applies the whole directory, not individual files — "build order"
means the order you *write* files, applying the whole directory after each
one. The loop for each remaining file (order and definitions of done are in
`DESIGN.md`, "Build Order and Dependencies" and "Definition of Done"):

```bash
cd opentofu/lab-01-vpc
# 1. Write or edit the next file in the build order (gwlb.tf, then tgw.tf, ...)
tofu init        # only needed once, or if providers/modules changed
tofu validate
tofu plan        # confirm: only the expected new resources, no surprise destroys
tofu apply
tofu plan        # after apply: should report "No changes" — if not, something drifted
```

Current build order (from `DESIGN.md`; files after vpc_hub/vpc_security do
not exist yet):

```
vpc_hub.tf, vpc_security.tf + modules/security-vpc/   (done)
→ gwlb.tf → tgw.tf → vpc_spoke.tf → vpc_onprem.tf → outputs.tf
```

### 3.3 What applying today's code creates

As of 2026-07-09, applying lab-01-vpc creates only: the hub VPC
(10.0.0.0/20, us-east-1) and the two security VPCs with their subnets, route
tables, and IGWs (us-east-1 and us-west-2). No GWLB, no TGW, no spokes, no
EC2 — those files don't exist yet. Nothing in the current code should incur
meaningful hourly cost (VPCs/subnets/route tables/IGWs are free).

### 3.4 Teardown

```bash
cd opentofu/lab-01-vpc
tofu plan -destroy   # review what will be removed
tofu destroy
```
