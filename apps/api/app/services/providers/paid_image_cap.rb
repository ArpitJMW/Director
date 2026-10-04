module Providers
  # Task 7: a hard ceiling on paid image calls. PAID_IMAGE_CALL_CAP defaults to 0,
  # so a paid image model refuses its first call unless the cap is raised. The
  # Image Lab raises it to 8 for its one run. The count lives in the process,
  # which is exactly the scope of one lab run.
  module PaidImageCap
    class Exhausted < StandardError; end

    @used = 0

    module_function

    def cap = ENV.fetch("PAID_IMAGE_CALL_CAP", "0").to_i
    def used = @used
    def reset! = @used = 0

    # Counts one paid image call, or refuses it once the cap is reached.
    def reserve!(provider:, model:)
      raise Exhausted, "paid image call cap reached (#{@used}/#{cap}); PAID_IMAGE_CALL_CAP limits paid image calls" if @used >= cap

      @used += 1
    end
  end
end
