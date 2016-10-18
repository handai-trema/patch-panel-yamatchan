# Software patch-panel.
class PatchPanel < Trema::Controller
  def start(_args)
    @patch = Hash.new { [] }
    @mirror = Hash.new { |h,k| h[k] = {} }
    logger.info 'PatchPanel started.'
  end

  def switch_ready(dpid)
    @patch[dpid] = []
    @patch[dpid].each do |port_a, port_b|
      delete_flow_entries dpid, port_a, port_b
      add_flow_entries dpid, port_a, port_b
    end
  end

  def create_patch(dpid, port_a, port_b)
    add_flow_entries dpid, port_a, port_b
    pair = port_a < port_b ? [port_a, port_b] : [port_b, port_a]
    @patch[dpid] << pair
   end

  def delete_patch(dpid, port_a, port_b)
    delete_flow_entries dpid, port_a, port_b
    @patch[dpid] -= [port_a, port_b].sort
  end

  def add_mirror(dpid, port_a, port_b)
    logger.info "#add_mirror"
    add_mirror_entries dpid, port_a, port_b
  end

  def list()
    str = ""

    @patch.each do |dpid, pairs|
      str += "#dpid = 0x#{dpid.to_s(16)}\n"
      pairs.each do |pair|
        str += "* #{pair[0]} <-> #{pair[1]}\n"
      end
      @mirror[dpid].each do |port_a, port_m|
        str += "+ #{port_a} --> #{port_m}\n"
      end
      str += "\n"
    end

    str
  end

  private

  def add_flow_entries(dpid, port_a, port_b)
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_a),
                      actions: SendOutPort.new(port_b))
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_b),
                      actions: SendOutPort.new(port_a))
  end

  def delete_flow_entries(dpid, port_a, port_b)
    send_flow_mod_delete(dpid, match: Match.new(in_port: port_a))
    send_flow_mod_delete(dpid, match: Match.new(in_port: port_b))
  end

  def add_mirror_entries(dpid, port_a, port_m)
    port_b = nil

    @patch[dpid].each do |pair|
      port_b = pair[1] if pair[0] == port_a
      port_b = pair[0] if pair[1] == port_a
    end

    return if port_b.nil?

    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_a),
                      actions: [
                        SendOutPort.new(port_b),
                        SendOutPort.new(port_m),
                      ])
    send_flow_mod_add(dpid,
                      match: Match.new(in_port: port_b),
                      actions: [
                        SendOutPort.new(port_a),
                        SendOutPort.new(port_m),
                       ])
    @mirror[dpid][port_a] = port_m
  end
end
