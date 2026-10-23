# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # Retries are declared per job (design specifications/02, Retries and rate
  # limits); Solid Queue does not retry failed jobs on its own.
  discard_on ActiveJob::DeserializationError
end
