module Api
  module V1
    # Base for controllers that expose owned resources. Enforces that every
    # action authorizes (spec §36) and that #index goes through a policy scope.
    class ResourceController < BaseController
      after_action :verify_authorized, unless: -> { action_name == "index" }
      after_action :verify_policy_scoped, if: -> { action_name == "index" }
    end
  end
end
