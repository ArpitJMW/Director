class AiGeneration < ApplicationRecord
  include HasPublicId
  has_public_id :gen

  KINDS = %w[
    research script scene_plan visual_prompt image video voice caption
    music fact_check quality_check preflight
  ].freeze
  PROVIDER_KINDS = %w[llm image voice music video].freeze
  STATUSES = %w[pending running succeeded failed].freeze

  belongs_to :project, optional: true
  belongs_to :scene, optional: true

  has_many :assets, dependent: :nullify
  has_many :scripts, dependent: :nullify
  has_many :voice_generations, dependent: :nullify
  has_many :generation_logs, dependent: :nullify

  validates :kind, inclusion: { in: KINDS }
  validates :provider_kind, inclusion: { in: PROVIDER_KINDS }
  validates :provider, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :cost_usd, numericality: { greater_than_or_equal_to: 0 }

  scope :succeeded, -> { where(status: "succeeded") }

  # Wraps a provider call, recording status, timing, tokens, cost and a log line
  # (spec §37). Yields the running record; the block returns a
  # Providers::LLM::Result. Re-raises on failure after marking the row failed.
  def self.track!(project:, kind:, provider:, model:, provider_kind: "llm", scene: nil, request: {})
    generation = create!(
      project: project, scene: scene, kind: kind, provider_kind: provider_kind,
      provider: provider, model: model, status: "running", request: request,
      started_at: Time.current
    )

    result = yield generation

    cost =
      if result.respond_to?(:cost_usd) && result.cost_usd
        result.cost_usd
      else
        Providers::Pricing.cost_usd(
          provider: result.provider, model: result.model,
          input_tokens: result.input_tokens, output_tokens: result.output_tokens
        )
      end

    generation.update!(
      status: "succeeded",
      finished_at: Time.current,
      latency_ms: ((Time.current - generation.started_at) * 1000).round,
      prompt_tokens: result.try(:input_tokens),
      completion_tokens: result.try(:output_tokens),
      total_tokens: result.try(:total_tokens),
      cost_usd: cost,
      provider_request_id: result.provider_request_id,
      response: response_summary(result)
    )
    GenerationLog.create!(
      project: project, ai_generation: generation, scene: scene, level: "info",
      stage: kind, message: "#{kind} via #{result.provider}/#{result.model}",
      data: { cost_usd: cost, tokens: result.try(:total_tokens) }
    )
    result
  rescue => e
    generation&.update(
      status: "failed", finished_at: Time.current,
      failure_reason: e.message, error: { class: e.class.name }
    )
    GenerationLog.create!(
      project: project, ai_generation: generation, scene: scene, level: "error",
      stage: kind, message: "#{kind} failed: #{e.message}"
    )
    raise
  end

  def self.response_summary(result)
    if result.respond_to?(:text)
      { stop_reason: result.stop_reason, text_length: result.text.length }
    else
      { content_type: result.try(:content_type), byte_size: result.try(:byte_size) }
    end
  end
  private_class_method :response_summary

  def duration_ms
    return latency_ms if latency_ms
    return unless started_at && finished_at

    ((finished_at - started_at) * 1000).round
  end
end
