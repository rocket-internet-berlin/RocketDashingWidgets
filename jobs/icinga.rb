# from  https://github.com/roidelapluie/dashing-scripts/blob/master/jobs/icinga.rb
# with modifications and additions by Markus Frosch <markus.frosch@netways.de>
# ... and more modifications by Stephen Hardisty @ Rocket!
require 'net/https'
require 'uri'

SCHEDULER.every '15s', first_in: 0 do |job|
  parameters = settings.use_icinga
  return unless parameters

  url = parameters.need(:url)
  username = parameters.want(:username)
  password = parameters.want(:password)

  truncator = RocketDashing::Truncator.new

  # host
  result = get_status_host(url, username, password, truncator)
  totals = result[:totals]

  moreinfo = []
  color = 'green'
  display = totals[:count]
  legend = ''

  if totals[:unhandled] > 0
    display = totals[:unhandled].to_s
    legend = 'unhandled'
    if totals[:down] > 0 or totals[:unreachable] > 0
      color = 'red'
    end
  end

  [:down, :unreachable, :ack, :downtime].each do |state|
    moreinfo << "#{totals[state]}  #{state}" if totals[state] > 0
  end

  send_event 'icinga-hosts', {
                               value: display,
                               moreinfo: moreinfo * ' | ',
                               color: color,
                               legend: legend
                           }

  send_event 'icinga-hosts-latest', {
                                      rows: result[:latest],
                                      moreinfo: result[:latest_moreinfo]
                                  }

  # service
  result = get_status_service(url, username, password, truncator)
  totals = result[:totals]

  moreinfo = []
  color = 'green'
  display = totals[:count]
  legend = ''

  if totals[:unhandled] > 0
    display = totals[:unhandled].to_s
    legend = 'unhandled'
    if totals[:critical] > 0
      color = 'red'
    elsif totals[:warning] > 0
      color = 'yellow'
    elsif totals[:unknown] > 0
      color = 'orange'
    end
  end

  [:critical, :warning, :ack, :downtime].each do |state|
    moreinfo << "#{totals[state]}  #{state}" if totals[state] > 0
  end

  send_event 'icinga-services', {
                                  value: display,
                                  moreinfo: moreinfo * ' | ',
                                  color: color,
                                  legend: legend
                              }

  send_event 'icinga-services-latest', {
                                         rows: result[:latest],
                                         moreinfo: result[:latest_moreinfo]
                                     }

end

def request_status(url, username, password, type)
  url_part = nil

  case type
    when 'host'
      url_part = 'style=hostdetail'
    when 'service'
      url_part = 'host=all&hoststatustypes=3'
    else
      throw "status type '#{type}' is not supported!"
  end

  uri = URI.parse("#{url}?#{url_part}&nostatusheader&jsonoutput&sorttype=1&sortoption=6")

  http = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https')
  request = Net::HTTP::Get.new(uri.request_uri)

  request.basic_auth(username, password) if username and password

  response = http.request(request)

  JSON.parse(response.body)['status']["#{type}_status"]
end

def get_status_service(url, username, password, truncator)
  service_status = request_status(url, username, password, 'service')

  latest = []
  latest_counter = 0
  totals = {
      unhandled: 0,
      warning: 0,
      critical: 0,
      unknown: 0,
      ack: 0,
      downtime: 0,
      count: 0
  }

  service_status.each { |status|
    totals[:count] += 1

    if status['in_scheduled_downtime']
      totals[:downtime] += 1
      next
    elsif status['has_been_acknowledged']
      totals[:ack] += 1
      next
    end

    has_problem = false
    case status['status']
      when 'CRITICAL'
        totals[:critical] += 1
        totals[:unhandled] += 1
        has_problem = true
      when 'WARNING'
        totals[:warning] += 1
        totals[:unhandled] += 1
        has_problem = true
      when 'UNKNOWN'
        totals[:unknown] += 1
        totals[:unhandled] += 1
        has_problem = truw
    end

    if has_problem
      latest_counter += 1
      if latest_counter <= 15
        latest.push({cols: [
                        {value: truncator.truncate(status['host_name'], 22)},
                        {value: status['status']},
                    ]})
        latest.push({cols: [
                        {value: truncator.truncate(status['service_description'], 22)},
                        {value: status['duration'].gsub(/^0d\s+(0h\s+)?/, '').gsub(/\s+\d+s$/, '')}
                    ]})
      end
    end
  }

  latest_moreinfo = "#{latest_counter} problems"
  latest_moreinfo += " | #{latest_counter - 15} not listed" if latest_counter > 15

  {
      totals: totals,
      latest: latest,
      latest_moreinfo: latest_moreinfo
  }
end

def get_status_host(url, username, password, truncator)
  host_status = request_status(url, username, password, 'host')

  latest = []
  latest_counter = 0
  totals = {
      unhandled: 0,
      unreachable: 0,
      down: 0,
      ack: 0,
      downtime: 0,
      count: 0
  }

  host_status.each { |status|
    totals[:count] += 1

    if status['in_scheduled_downtime']
      totals[:downtime] += 1
      next
    elsif status['has_been_acknowledged']
      totals[:ack] += 1
      next
    end

    has_problem = false
    case status['status']
      when 'DOWN'
        totals[:down] += 1
        totals[:unhandled] += 1
        has_problem = true
      when 'UNREACHABLE'
        totals[:unreachable] += 1
        totals[:unhandled] += 1
        has_problem = true
    end

    if has_problem
      latest_counter += 1
      if latest_counter <= 15
        latest.push({cols: [
                        {value: truncator.truncate(status['host_name'], 22)},
                        {value: status['status']},
                    ]})
        latest.push({cols: [
                        {
                            value: status['duration'].gsub(/^0d\s+(0h\s+)?/, ''),
                            colspan: 2
                        },
                    ]})
      end
    end
  }

  latest_moreinfo = "#{latest_counter} problems"
  latest_moreinfo += " | #{latest_counter - 15} not listed" if latest_counter > 15

  {
      totals: totals,
      latest: latest,
      latest_moreinfo: latest_moreinfo
  }
end

