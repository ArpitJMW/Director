class ApplicationController < ActionController::API
  # Devise leans on a few bits of ActionController::Base that API mode drops.
  include ActionController::MimeResponds

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable

  private

  def render_not_found(error)
    render json: { error: "not_found", message: error.message }, status: :not_found
  end

  def render_unprocessable(error)
    render json: {
      error: "unprocessable_entity",
      messages: error.record.errors.full_messages
    }, status: :unprocessable_content
  end
end
