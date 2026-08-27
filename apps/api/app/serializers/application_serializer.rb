# Base for plain-object serializers. Subclasses implement `#as_json`.
#
#   ProjectSerializer.call(project)   # => Hash
#   ProjectSerializer.list(projects)  # => [Hash, ...]
class ApplicationSerializer
  def self.call(record, **opts)
    return nil if record.nil?

    new(record, **opts).as_json
  end

  def self.list(records, **opts)
    records.map { |record| call(record, **opts) }
  end

  def initialize(record, **opts)
    @record = record
    @opts = opts
  end

  attr_reader :record, :opts

  def as_json
    raise NotImplementedError
  end

  private

  def ts(value)
    value&.iso8601
  end
end
