module RocketDashing
  class Truncator
    def truncate(string, length)
      string.length > length ?
          string.slice(0..length-1) + '...' :
          string
    end
  end
end