module MeetingsHelper
  # Per-participant relativistic data for one meeting, shared by the row's
  # mini dilation bars (_meeting) and the expandable detail
  # (_relativistic_info). Memoized per meeting so each system's JSON is
  # resolved once per render.
  #
  # @return [Hash] { name => { system_id:, system:, body:, dilation: } } in participant order
  def meeting_participants_info(meeting)
    @meeting_participants_info ||= {}
    @meeting_participants_info[meeting.id] ||= begin
      calculator = @relativistic_calculator || RelativisticCalculator.new
      participant_systems = meeting.participant_systems_hash

      meeting.participants_array.to_h do |name|
        system_id = if meeting.is_inter_system && participant_systems.present?
          participant_systems[name]
        else
          meeting.system_id
        end
        system = system_id ? (@systems_by_id&.dig(system_id) || System.find_by(id: system_id)) : nil
        body = system&.load_system_data&.dig("bodies")&.find { |b| b["name"] == name }

        [ name, { system_id: system_id, system: system, body: body, dilation: calculator.calculate_time_dilation(body, system_id) } ]
      end
    end
  end
end
