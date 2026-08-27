Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect(
    "llm" => "LLM"
  )
end
