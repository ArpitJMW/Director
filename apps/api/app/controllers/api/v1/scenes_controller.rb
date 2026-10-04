module Api
  module V1
    class ScenesController < ResourceController
      before_action :set_scene, only: [ :show, :update ]

      # Phase 1 Task 3: the only two production methods that actually have an
      # executor (Media::ProductionDispatcher). The web UI's method switch may
      # only ever send one of these — never the full Scene::ASSET_STRATEGIES
      # list (image_to_video/animation/chart/screen/user_asset/mixed have no
      # executor either).
      EDITABLE_ASSET_STRATEGIES = %w[image text].freeze

      # GET /api/v1/projects/:project_id/scenes
      def index
        project = Project.find_by_public_id!(params[:project_id])
        authorize project, :show?
        scenes = policy_scope(Scene).where(project: project).order(:position)
        render json: { scenes: SceneSerializer.list(scenes.includes(:project, :selected_asset)) }
      end

      def show
        authorize @scene
        render json: { scene: SceneSerializer.call(@scene) }
      end

      # Creator scene corrections (spec §10 — storyboard editor), extended
      # Phase 1 Task 3 with the Director panel's fields: asset_strategy
      # (cascades to shots + flags regeneration), direction (camera/
      # transition/overlay/text_style — re-render only, never regeneration),
      # and per-shot direction edits nested under `shots`. Regeneration of AI
      # content itself is still the separate Phase 3 pipeline action
      # (POST .../assets/regenerate) — this endpoint only ever flags that it's
      # needed, never triggers it.
      #
      # All-or-nothing: catalog values are validated up front (never a
      # DirectionParser-style silent coerce — a human editing the UI gets a
      # real 422, not a value quietly swapped out from under them) before
      # anything is written, so an invalid request never leaves a partial edit.
      def update
        authorize @scene

        errors = validate_update(scene_params)
        return render json: { error: "unprocessable_entity", messages: errors }, status: :unprocessable_entity if errors.any?

        apply_update!(scene_params)
        render json: { scene: SceneSerializer.call(@scene.reload) }
      end

      private

      def set_scene
        @scene = Scene.find_by_public_id!(params[:id])
      end

      def scene_params
        params.require(:scene).permit(
          :narration, :visual_type, :visual_prompt, :caption, :animation,
          :transition, :duration_seconds, :background_music_level, :notes,
          :asset_strategy, :purpose, :action, :mood,
          direction: [ :camera_motion, :camera_intensity, :transition_in, :text_style, :number, :unit,
                       items: [], overlay: [ :type, :text, :value ] ],
          shots: [ :id, direction: [ :camera_motion, :camera_intensity, overlay: [ :type, :text, :value ] ] ]
        )
      end

      # --- Validation (reject, never silently coerce — Task 3 Step 2) -------

      def validate_update(attrs)
        errors = []
        if attrs[:asset_strategy].present? && !EDITABLE_ASSET_STRATEGIES.include?(attrs[:asset_strategy])
          errors << "asset_strategy must be one of #{EDITABLE_ASSET_STRATEGIES.join(', ')}"
        end
        # visual_type itself keeps its pre-Task-3 validation (the model's own
        # `inclusion: { in: VISUAL_TYPES }`, unchanged) — it's a broader,
        # pre-existing free-form label (the plain "Edit scene" text form has
        # always allowed the full list). asset_strategy above is the new,
        # stricter "only what's actually executable" gate Task 3 asks for.
        if attrs[:transition].present? && !Scene::TRANSITIONS.include?(attrs[:transition])
          errors << "transition must be one of #{Scene::TRANSITIONS.join(', ')}"
        end
        errors.concat(validate_direction(attrs[:direction], scope: "direction")) if attrs[:direction]
        Array(attrs[:shots]).each_with_index do |shot_attrs, i|
          errors << "shots[#{i}].id is required" if shot_attrs[:id].blank?
          errors.concat(validate_direction(shot_attrs[:direction], scope: "shots[#{i}].direction")) if shot_attrs[:direction]
        end
        errors
      end

      def validate_direction(direction, scope:)
        return [] unless direction

        errors = []
        if direction[:camera_motion].present? && !Scene::CAMERA_MOTIONS.include?(direction[:camera_motion])
          errors << "#{scope}.camera_motion #{direction[:camera_motion].inspect} must be one of #{Scene::CAMERA_MOTIONS.join(', ')}"
        end
        if direction[:camera_intensity].present? && !Scene::CAMERA_INTENSITIES.include?(direction[:camera_intensity])
          errors << "#{scope}.camera_intensity #{direction[:camera_intensity].inspect} must be one of #{Scene::CAMERA_INTENSITIES.join(', ')}"
        end
        if direction[:transition_in].present? && !Scene::TRANSITIONS.include?(direction[:transition_in])
          errors << "#{scope}.transition_in #{direction[:transition_in].inspect} must be one of #{Scene::TRANSITIONS.join(', ')}"
        end
        if direction[:text_style].present? && !Scene::TEXT_STYLES.include?(direction[:text_style])
          errors << "#{scope}.text_style #{direction[:text_style].inspect} must be one of #{Scene::TEXT_STYLES.join(', ')}"
        end
        if direction[:overlay] && direction[:overlay][:type].present? && !Scene::OVERLAY_TYPES.include?(direction[:overlay][:type])
          errors << "#{scope}.overlay.type #{direction[:overlay][:type].inspect} must be one of #{Scene::OVERLAY_TYPES.join(', ')}"
        end
        errors
      end

      # --- Apply (already validated above) -----------------------------------

      def apply_update!(attrs)
        Scene.transaction do
          apply_asset_strategy!(attrs[:asset_strategy]) if attrs[:asset_strategy].present?
          apply_direction!(@scene, attrs[:direction]) if attrs[:direction]
          Array(attrs[:shots]).each { |shot_attrs| apply_shot_update!(shot_attrs) }
          @scene.update!(plain_scene_attrs(attrs))
        end
      end

      def plain_scene_attrs(attrs)
        attrs.except(:asset_strategy, :direction, :shots, :visual_type).tap do |h|
          # visual_type is applied via apply_asset_strategy! when the strategy
          # itself changed; otherwise a directly-given visual_type (already
          # validated against PLANNABLE_VISUAL_TYPES above) still applies.
          h[:visual_type] = attrs[:visual_type] if attrs[:visual_type].present? && attrs[:asset_strategy].blank?
        end
      end

      # Task 3 Step 2: switching production method invalidates whatever asset
      # exists (an image can't become a text card or vice versa) — cascades
      # to shots (text units never have shots) and flags regeneration by
      # reverting status to "pending", the same status every unit starts at
      # before its first generation. Never auto-regenerates — that stays the
      # separate, explicit POST .../assets/regenerate action.
      def apply_asset_strategy!(new_strategy)
        return if new_strategy == @scene.asset_strategy

        if new_strategy == "text"
          @scene.shots.destroy_all
          @scene.visual_type = "text_animation"
        else
          @scene.visual_type = "image" if @scene.visual_type == "text_animation"
        end
        @scene.asset_strategy = new_strategy
        @scene.status = "pending"
      end

      # Direction-only edit — the existing asset/audio is still valid, only
      # how it's PRESENTED changed, so status (regeneration) is untouched;
      # the project-level `needs_rerender` (SceneSerializer) picks up the
      # `updated_at` bump from this save automatically.
      def apply_direction!(record, direction)
        if direction[:camera_motion]
          # Scene stores it inside the `camera` jsonb (alongside shot_type/
          # framing from the planner); Shot has its own plain string column.
          if record.is_a?(Scene)
            record.camera = record.camera.merge("movement" => direction[:camera_motion])
          else
            record.camera_movement = direction[:camera_motion]
          end
        end
        if direction[:camera_intensity]
          record.motion = record.motion.merge("intensity" => direction[:camera_intensity])
        end
        if record.is_a?(Scene) && direction[:transition_in]
          record.transition = direction[:transition_in]
        end
        if direction.key?(:overlay)
          record.metadata = record.metadata.merge("overlay" => normalize_overlay(direction[:overlay]))
        end
        if record.is_a?(Scene) && (direction[:text_style] || direction[:items] || direction.key?(:number) || direction[:unit])
          existing = record.metadata["direction_text"] || {}
          updated = existing.merge(
            {
              "text_style" => direction[:text_style],
              "items" => direction[:items] && Array(direction[:items]).map(&:to_s),
              "number" => direction[:number],
              "unit" => direction[:unit]
            }.compact
          )
          record.metadata = record.metadata.merge("direction_text" => updated)
        end
      end

      def normalize_overlay(overlay)
        return nil if overlay.blank? || overlay[:type].blank? || overlay[:type] == "none"

        { "type" => overlay[:type], "text" => overlay[:text].presence, "value" => overlay[:value].presence }.compact
      end

      # Task 4.1 real-run bug fix: this used to be `find_by!`, which raised
      # (and rolled back the WHOLE update, including unrelated scene-level
      # direction fields the user also just set) whenever a shot's id had
      # gone stale between the Direct panel loading its initial state and
      # the user clicking Save — a real race with shot (re)generation still
      # settling right after the storyboard checkpoint is reached, caught by
      # Task 4.1's real Playwright run. A vanished shot has nothing left to
      # update, so skip it rather than failing the whole request over it.
      def apply_shot_update!(shot_attrs)
        shot = @scene.shots.find_by(public_id: shot_attrs[:id])
        return if shot.nil?

        apply_direction!(shot, shot_attrs[:direction]) if shot_attrs[:direction]
        shot.save!
      end
    end
  end
end
