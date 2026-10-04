module QualityCheck
  # Writes one unit's QA state into its own metadata jsonb (Scene or Shot), the
  # same place the Director's overlay/direction already live. No new table, no
  # migration: the badge and the summary both read this key.
  module Store
    module_function

    def write(unit, status:, issues:, repair: nil, vision: nil)
      qa = (unit.metadata || {}).fetch("qa", {}).merge(
        "status" => status,
        "issues" => issues,
        "checked_at" => Time.current.iso8601
      )
      qa["repair"] = repair if repair
      qa["vision"] = vision if vision
      unit.update!(metadata: (unit.metadata || {}).merge("qa" => qa))
    end

    # The vision verdict for the image currently attached to this unit, if it was
    # already reviewed. Reusing it saves a vision call when nothing has changed.
    def reusable_vision(unit)
      vision = read(unit).to_h["vision"]
      return nil unless vision && unit.selected_asset && vision["asset_id"] == unit.selected_asset.public_id

      vision
    end

    def read(unit) = (unit.metadata || {})["qa"]

    def repair_attempts(unit) = read(unit).to_h.dig("repair", "attempts").to_i
  end
end
