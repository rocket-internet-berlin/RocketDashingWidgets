module RocketDashing
  class JobParameters
    def initialize settings
      @settings = settings
    end

    def need parameter
      @settings[parameter.to_sym] || throw("No such parameter '#{parameter}' in config.ru")
    end

    def want parameter
      @settings[parameter.to_sym]
    end
  end
end