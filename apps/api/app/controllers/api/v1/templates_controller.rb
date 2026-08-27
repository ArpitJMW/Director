module Api
  module V1
    class TemplatesController < ResourceController
      def index
        templates = policy_scope(Template).includes(:latest_version, :preview_asset).order(:name)
        render json: { templates: TemplateSerializer.list(templates) }
      end

      def show
        template = Template.find_by_public_id!(params[:id])
        authorize template
        render json: { template: TemplateSerializer.call(template) }
      end
    end
  end
end
