# Values for the customer domain, dev environment. The .tf files are identical across domain
# repositories and environments; only this file and state.config differ (design §6.1).
business             = "customer"
env                  = "dev"
tier                 = "nonprod"
region               = "australia-southeast1"
tf_state_bucket      = "tfstate-pltfrm-ngnrng"
billing_project      = ""
manage_access_groups = false

components = {
  classifier          = false
  steward_inbox       = false
  access_request_gate = false
  reconciler          = false
  explainer           = false
  scan_generator      = false
  sdp_notifications   = false
  access_request_sink = false
  data_access_sink    = false
  policy_tags         = false
  evaluator_modules   = ["c12", "c14"]
}

# P6-39 reference pipeline: Cloud Run jobs and the daily scheduler. Off until the image exists.
# Referenced by digest: dda-pipelines has immutable tags. VERIFY IN BUILD (estate): replace the
# placeholder digest with the PIPELINE_IMAGE line printed by pipelines/cloudbuild.yaml.
pipeline = {
  enabled  = false
  image    = "australia-southeast1-docker.pkg.dev/pltfrm-ngnrng/dda-pipelines/customer-pipeline@sha256:0000000000000000000000000000000000000000000000000000000000000000"
  schedule = "0 5 * * *"
  timezone = "Australia/Sydney"
}
