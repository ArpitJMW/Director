module Api
  module V1
    class PreflightReportsController < ResourceController
      # GET /api/v1/projects/:id/preflight  — latest report for the project
      def show
        project = Project.find_by_public_id!(params[:id])
        authorize project, :show?

        report = project.preflight_reports.order(created_at: :desc).first
        return head :no_content if report.nil?

        authorize report
        render json: { preflight: PreflightReportSerializer.call(report) }
      end
    end
  end
end
