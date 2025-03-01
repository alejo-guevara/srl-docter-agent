#!/bin/bash

# Sample script to provision SRLinux using gnmic
ROLE="$1"  # "spine" or "leaf"
INTF="$2"
IP_PREFIX="$3"
PEER="$4"         # 'host' for Linux nodes
PEER_IP="$5"
AS="$6"
ROUTER_ID="$7"
PEER_AS_MIN="$8"
PEER_AS_MAX="$9"
LINK_PREFIX="${10}"  # IP subnet used for allocation of IPs to BGP peers

temp_file=$(mktemp --suffix=.json)
_IP127="${IP_PREFIX//\/31/\/127}"
cat > $temp_file << EOF
{
  "description": "To $PEER",
  "admin-state": "enable",
  "subinterface": [
    {
      "index": 0,
      "admin-state": "enable",
      "ipv4": {
        "address": [
          {
            "ip-prefix": "$IP_PREFIX"
          }
        ]
      },
      "ipv6": {
        "address": [
          {
            "ip-prefix": "2001::${_IP127//\./:}"
          }
        ]
      }
    }
  ]
}
EOF

# For now, assume that the interface is already added to the default network-instance; only update its IP address
/sbin/ip netns exec srbase-mgmt /usr/local/bin/gnmic -a 127.0.0.1:57400 -u admin -p admin --skip-verify -e json_ietf set \
  --replace-path /interface[name=$INTF] --replace-file $temp_file
exitcode=$?

# Enable BFD, except for host facing interfaces
if [[ "$PEER" != "host" ]]; then
cat > $temp_file << EOF
{
 "admin-state" : "enable",
 "desired-minimum-transmit-interval" : 250000,
 "required-minimum-receive" : 250000,
 "detection-multiplier" : 3
}
EOF

/sbin/ip netns exec srbase-mgmt /usr/local/bin/gnmic -a 127.0.0.1:57400 -u admin -p admin --skip-verify -e json_ietf set \
  --replace-path /bfd/subinterface[id=${INTF}.0] --replace-file $temp_file
exitcode=$?
fi

# Set loopback IP, if provided
if [[ "$ROUTER_ID" != "" ]]; then
cat > $temp_file << EOF
{
  "admin-state": "enable",
  "subinterface": [
    {
      "index": 0,
      "admin-state": "enable",
      "ipv4": {
        "address": [
          {
            "ip-prefix": "$ROUTER_ID/32"
          }
        ]
      },
      "ipv6": {
        "address": [
          {
            "ip-prefix": "2001::${ROUTER_ID//\./:}/128"
          }
        ]
      }
    }
  ]
}
EOF
/sbin/ip netns exec srbase-mgmt /usr/local/bin/gnmic -a 127.0.0.1:57400 -u admin -p admin --skip-verify -e json_ietf set \
  --replace-path /interface[name=lo0] --replace-file $temp_file
exitcode+=$?

cat > $temp_file << EOF
{
  "router-id": "$ROUTER_ID",
  "admin-state": "enable",
  "version": "ospf-v3",
  "address-family": "ipv6-unicast",
  "max-ecmp-paths": 4,
  "area": [
    {
      "area-id": "0.0.0.0",
      "interface": [
        {
          "interface-name": "ethernet-1/1.0",
          "interface-type": "point-to-point"
        },
        {
          "interface-name": "lo0.0",
          "interface-type": "broadcast",
          "passive": true
        }
      ]
    }
  ]
}
EOF
/sbin/ip netns exec srbase-mgmt /usr/local/bin/gnmic -a 127.0.0.1:57400 -u admin -p admin --skip-verify -e json_ietf set \
  --update-path /network-instance[name=default]/protocols/ospf/instance[name=main] --update-file $temp_file
exitcode+=$?

if [[ "$ROLE" == "spine" ]]; then
IFS='' read -r -d '' DYNAMIC_NEIGHBORS << EOF
"dynamic-neighbors": {
    "accept": {
      "match": [
        {
          "prefix": "$LINK_PREFIX",
          "peer-group": "leaves",
          "allowed-peer-as": [
            "$PEER_AS_MIN..$PEER_AS_MAX"
          ]
        }
      ]
    }
  },
"failure-detection": { "enable-bfd" : true, "fast-failover" : true },
"group": [
    {
      "group-name": "fellow-spines",
      "admin-state": "enable",
      "peer-as": $AS
    },
    {
      "group-name": "leaves",
      "admin-state": "enable"
    }
  ],
EOF
else
IFS='' read -r -d '' DYNAMIC_NEIGHBORS << EOF
"group": [
    {
      "group-name": "spines",
      "admin-state": "enable",
      "failure-detection": { "enable-bfd" : true, "fast-failover" : true },
      "peer-as": $PEER_AS_MIN
    },
    {
      "group-name": "hosts",
      "admin-state": "enable",
      "peer-as": $AS
    }
],
EOF
fi

cat > $temp_file << EOF
{
  "admin-state": "enable",
  "autonomous-system": $AS,
  "router-id": "$ROUTER_ID",
  $DYNAMIC_NEIGHBORS
  "ipv4-unicast": {
    "multipath": {
      "max-paths-level-1": 4,
      "max-paths-level-2": 4
    }
  },
  "ipv6-unicast": {
    "multipath": {
      "max-paths-level-1": 4,
      "max-paths-level-2": 4
    }
  },
  "route-advertisement": {
    "rapid-withdrawal": true
  }
}

EOF

# Replace allows max 1 peer, TODO only add neighbors when already configured?
if [[ "$PEER" != "host" ]]; then
/sbin/ip netns exec srbase-mgmt /usr/local/bin/gnmic -a 127.0.0.1:57400 -u admin -p admin --skip-verify -e json_ietf set \
  --update-path /network-instance[name=default]/protocols/bgp --update-file $temp_file
exitcode+=$?
fi
fi # if router_id provided, first time only

if [[ "$PEER_IP" != "*" ]]; then
_IP="$PEER_IP"
if [[ "$PEER" == "host" ]]; then
PEER_GROUP="hosts"
_IP="2001::${PEER_IP//\./:}" # Use ipv6 for hosts
elif [[ "$ROLE" == "spine" ]]; then
PEER_GROUP="fellow-spines"
else
PEER_GROUP="spines"
fi

cat > $temp_file << EOF
{
  "admin-state": "enable",
  "peer-group": "$PEER_GROUP"
}
EOF
/sbin/ip netns exec srbase-mgmt /usr/local/bin/gnmic -a 127.0.0.1:57400 -u admin -p admin --skip-verify -e json_ietf set \
  --update-path /network-instance[name=default]/protocols/bgp/neighbor[peer-address=$_IP] --update-file $temp_file
exitcode+=$?
fi

rm -f $temp_file
exit $exitcode
