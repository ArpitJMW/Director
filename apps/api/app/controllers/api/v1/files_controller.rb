module Api
  module V1
    # Serves objects from the disk storage backend via a signed, expiring URL.
    # The HMAC token is the capability — no session needed (same model as an S3
    # presigned URL). Inactive when STORAGE_BACKEND=s3 (those URLs hit S3/R2).
    class FilesController < ApplicationController
      def show
        storage = Storage.service
        unless storage.is_a?(Storage::DiskAdapter)
          return head :not_found
        end

        key = params[:key].to_s
        unless storage.verify(key: key, token: params[:token], expires: params[:expires])
          return head :forbidden
        end
        return head :not_found unless storage.exists?(key: key)

        send_data storage.download(key: key),
          type: Marcel::MimeType.for(name: key),
          disposition: "inline"
      end
    end
  end
end
