require 'aws'

cloudwatch = nil

def format_triggered_alarm alarm
  truncator = RocketDashing::Truncator.new

  {cols: [
      {value: truncator.truncate(alarm[:alarm_name], 27)},
      {value: truncator.truncate(alarm[:state_value], 5)}
  ]}
end

SCHEDULER.every '2m', first_in: 0 do |job|
  parameters = settings.use_cloudwatch_alarms
  return unless parameters

  cloudwatch ||= AWS::CloudWatch::Client.new(
      region: parameters.need(:region),
      access_key_id: parameters.need(:access_key_id),
      secret_access_key: parameters.need(:secret_access_key)
  )

  ok_alarm_count = 0
  total_alarms_count = 0
  triggered_alarms = []
  has_alarms = false

  cloudwatch.describe_alarms(max_records: 100, state_value: 'OK').metric_alarms.each do |ok_alarm|
    total_alarms_count += 1
    ok_alarm_count += 1
  end

  cloudwatch.describe_alarms(max_records: 100, state_value: 'ALARM').metric_alarms.each do |triggered_alarm|
    has_alarms = true
    total_alarms_count += 1

    triggered_alarms << format_triggered_alarm(triggered_alarm)
  end

  cloudwatch.describe_alarms(max_records: 100, state_value: 'INSUFFICIENT_DATA').metric_alarms.each do |insufficient_data|
    total_alarms_count += 1
    triggered_alarms << format_triggered_alarm(insufficient_data)
  end

  color = 'green'
  if has_alarms
    color = 'red'
  elsif !triggered_alarms.empty?
    color = 'yellow'
  end

  send_event 'cloudwatch-alarms-ok', {
                                       value: "#{ok_alarm_count}/#{total_alarms_count}",
                                       color: color
                                   }
  send_event 'cloudwatch-alarms-failed', {
                                           rows: triggered_alarms,
                                           moreinfo: "#{triggered_alarms.count} problems",
                                           color: color
                                       }
end