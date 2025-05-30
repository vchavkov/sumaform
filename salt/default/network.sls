{% if grains.get('ipv6')['enable'] %}

ipv6_enable_all:
  sysctl.present:
    - name: net.ipv6.conf.all.disable_ipv6
    - value: 0

{# net.ipv6.conf.all.accept_ra cannot be used, we have to proceed one interface at a time #}
{% set ifaces = grains.get('ip6_interfaces').keys() %}

{% if grains.get('ipv6')['accept_ra'] %}

{% for iface in ifaces %}
{% if not iface.startswith("flannel") %}
ipv6_accept_ra_{{ iface }}:
  sysctl.present:
    - name: net.ipv6.conf.{{ iface }}.accept_ra
    - value: 2
{% endif %}
{% endfor %}

{% if grains['osfullname'] in ['SLE Micro', 'SL-Micro', 'openSUSE Leap Micro'] and (grains['osrelease'] != '5.1' and grains['osrelease'] != '5.2') %}
{% set conname = salt.cmd.run_stdout('nmcli -g GENERAL.CONNECTION device show eth0') %}
avoid_network_manager_messing_up:
  cmd.run:
    - name: |
        nmcli connection modify "{{ conname }}" ipv6.addr-gen-mode eui64
        nmcli device modify eth0 ipv6.addr-gen-mode eui64
{% endif %}

{% else %}

{% for iface in ifaces %}
ipv6_reject_ra_{{ iface }}:
  sysctl.present:
    - name: net.ipv6.conf.{{ iface }}.accept_ra
    - value: 0

delete_existing_dynamic_addresses_{{ iface }}:
  cmd.run:
    - name: |
        for dynaddr in $(ip -6 a s dev {{ iface }} | grep 'inet6 2' | awk '{print $2}'); do
          ip -6 a d $dynaddr dev {{ iface }}
        done

{% if grains['os'] == 'SUSE' %}
avoid_wicked_messing_up_{{ iface }}:
  file.replace:
    - name: /etc/sysconfig/network/ifcfg-{{ iface }}
    - pattern: "BOOTPROTO *= *[Dd][Hh][Cc][Pp] *$"
    - repl: "BOOTPROTO=dhcp4"
    - ignore_if_missing: true
{% endif %}
{% endfor %}

{% if grains['os'] == 'Ubuntu' %}
avoid_networkd_messing_up:
  file.append:
    - name: /etc/netplan/01-netcfg.yaml
    - text: "      accept-ra: no"
  cmd.run:
    - name: 'netplan apply'
{% endif %}

{% endif %}

{% else %}

ipv6_disable_all:
  sysctl.present:
    - name: net.ipv6.conf.all.disable_ipv6
    - value: 1

{% endif %}

{% if grains['osfullname'] in ['SLE Micro', 'SL-Micro', 'openSUSE Leap Micro'] and (grains['osrelease'] != '5.1' and grains['osrelease'] != '5.2') %}
{% set conname2 = salt.cmd.run_stdout('nmcli -g GENERAL.CONNECTION device show eth1', ignore_retcode=true) %}
{% if conname2 != '' %}
enable_dhcp_on_eth1:
  cmd.run:
    - name: |
        nmcli connection modify "{{ conname2 }}" ipv4.method auto
        nmcli device modify eth1 ipv4.method auto
{% endif %}
{% endif %}

{% if grains['os_family'] == 'RedHat' and grains.get('osmajorrelease', None)|int() == 6 %}
mdns_iptables:
  iptables.insert:
    - position: 1
    - table: filter
    - chain: INPUT
    - jump: ACCEPT
    - match: state
    - connstate: NEW
    - dport: 5353
    - protocol: udp
    - save: True
{% endif %}

{% if grains['os'] == 'Debian' %}
comment_hosts_fqdn:
  file.replace:
    - name: /etc/hosts
    - pattern: "^127.0.1.1 "
    - repl: "#127.0.1.1 "
    - count: 1

cloud_init_disable_manage_hosts:
  file.replace:
    - name: /etc/cloud/cloud.cfg
    - pattern: "^manage_etc_hosts: true$"
    - repl: "manage_etc_hosts: false"
    - append_if_not_found: true
{% endif %}
