module Ai
  # Parses and validates the Director's "direction" object (Phase 1 Task 4)
  # out of one scene/shot's raw LLM JSON. Shared between Ai::ScenePlannerService
  # and Ai::ShotPlanner so both validate against the exact same catalog
  # (Scene::CAMERA_MOTIONS / TRANSITIONS / CAMERA_INTENSITIES / OVERLAY_TYPES /
  # TEXT_STYLES — mirrored in packages/video-schema) and log the same way on
  # an invalid choice. Absent fields are never logged (most units only use a
  # few of these) — only a present-but-invalid value falls back with a
  # warning, per Task 4's "never silent" rule.
  class DirectionParser
    def initialize(project:, unit_key:)
      @project = project
      @unit_key = unit_key
    end

    # @param raw [Hash, nil] the unit's raw "direction" hash from the LLM
    # @return [Hash] symbol-keyed, already-validated fields. Only present
    #   when meaningful (`.compact`), so callers can just merge what's there.
    def parse(raw)
      raw = raw.is_a?(Hash) ? raw : {}
      {
        transition: coerce(raw["transition_in"], Scene::TRANSITIONS, field: "transition_in"),
        camera_movement: coerce(raw["camera_motion"], Scene::CAMERA_MOTIONS, field: "camera_motion"),
        intensity: coerce(raw["camera_intensity"], Scene::CAMERA_INTENSITIES, field: "camera_intensity"),
        overlay: parse_overlay(raw["overlay"]),
        text_style: coerce(raw["text_style"], Scene::TEXT_STYLES, field: "text_style"),
        items: Array(raw["items"]).map { |i| i.to_s.strip }.reject(&:blank?).first(6).presence,
        number: raw["number"].is_a?(Numeric) || raw["number"].is_a?(String) ? raw["number"] : nil,
        unit: raw["unit"].to_s.strip.presence,
        direction_reason: raw["direction_reason"].to_s.strip.presence
      }.compact
    end

    private

    # nil/blank fallback is intentionally omitted from the returned hash
    # entirely (via the caller's `.compact`) rather than written as an
    # explicit default — an ABSENT field means "the LLM didn't address this,
    # leave existing/default behavior alone", which is different from "the
    # LLM explicitly chose an invalid value" (logged + a real fallback).
    def coerce(value, allowed, field:)
      return nil if value.blank?
      return value if allowed.include?(value)

      GenerationLog.create!(
        project: @project, level: "warn", stage: "direction",
        message: "#{@unit_key}: invalid #{field} #{value.inspect} (not in catalog), ignoring"
      )
      nil
    end

    def parse_overlay(raw)
      return nil unless raw.is_a?(Hash)

      type = coerce(raw["type"], Scene::OVERLAY_TYPES, field: "overlay.type")
      return nil if type.nil? || type == "none"

      { "type" => type, "text" => raw["text"].to_s.strip.presence, "value" => raw["value"].to_s.strip.presence }.compact
    end
  end
end
