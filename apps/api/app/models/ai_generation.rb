class AiGeneration < ApplicationRecord
  include HasPublicId
  has_public_id :gen

  KINDS = %w[
    research script script_condense script_expand scene_plan shot_plan visual_prompt look image video voice caption
    music fact_check quality_check preflight setting
  ].freeze
  PROVIDER_KINDS = %w[llm image voice music video].freeze
  STATUSES = %w[pending running succeeded failed].freeze

  belongs_to :project, optional: true
  belongs_to :scene, optional: true
  belongs_to :shot, optional: true

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
  # (spec §37). Yields the running record; the block returns either a single
  # Result or (Phase 1 Task 2.4 — batch TTS) an Array of them, when one
  # provider call produced several logical results (e.g. one Gemini TTS call
  # split across several scenes). An Array is stored as ONE AiGeneration —
  # every scene links to it via voice_generation.ai_generation_id — with cost
  # summed and token/response bookkeeping taken from the first result,
  # matching how a batch call reports a single latency/response envelope.
  # Re-raises on failure after marking the row failed.
  def self.track!(project:, kind:, provider:, model:, provider_kind: "llm", scene: nil, shot: nil, request: {})
    generation = create!(
      project: project, scene: scene, shot: shot, kind: kind, provider_kind: provider_kind,
      provider: provider, model: model, status: "running", request: request,
      started_at: Time.current
    )

    result = yield generation
    batch = result.is_a?(Array)
    # A batch array may contain nil entries (a chunk that failed after
    # retries — see Providers::Voice::Base#synthesize_batch) as long as at
    # least one entry succeeded; any real entry works equally well as the
    # representative for provider/model bookkeeping below.
    primary = batch ? result.compact.first : result

    cost =
      if batch
        result.sum { |r| r.try(:cost_usd).to_f }
      elsif primary.respond_to?(:cost_usd) && primary.cost_usd
        primary.cost_usd
      else
        Providers::Pricing.cost_usd(
          provider: primary.provider, model: primary.model,
          input_tokens: primary.input_tokens, output_tokens: primary.output_tokens
        )
      end

    generation.update!(
      status: "succeeded",
      finished_at: Time.current,
      latency_ms: ((Time.current - generation.started_at) * 1000).round,
      prompt_tokens: primary.try(:input_tokens),
      completion_tokens: primary.try(:output_tokens),
      total_tokens: primary.try(:total_tokens),
      cost_usd: cost,
      provider_request_id: batch ? result.compact.filter_map(&:provider_request_id).join(",").presence : primary.provider_request_id,
      response: estimate_response(batch ? result.compact : [ primary ], batch ? result.size : nil)
    )
    GenerationLog.create!(
      project: project, ai_generation: generation, scene: scene, level: "info",
      stage: kind, message: "#{kind} via #{primary.provider}/#{primary.model}#{" (batch of #{result.size})" if batch}",
      data: { cost_usd: cost, tokens: primary.try(:total_tokens) }
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

  # Task 6 F: the list-price estimate sits beside the billed cost_usd, so a
  # free-tier call can show $0 billed and still say what it would have cost.
  def self.estimate_response(results, batch_size)
    primary = results.first
    base = response_summary(primary)
    base = base.merge(batch_size: batch_size) if batch_size
    estimates = results.filter_map { |r| r.try(:raw).is_a?(Hash) ? r.raw[:estimated_cost_usd] : nil }
    estimates.any? ? base.merge(estimated_cost_usd: estimates.sum.to_f.round(6)) : base
  end
  private_class_method :estimate_response

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
