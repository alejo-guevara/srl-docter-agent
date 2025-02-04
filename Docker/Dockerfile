ARG SR_LINUX_RELEASE
FROM srl/auto-config:$SR_LINUX_RELEASE
# FROM srl/custombase:$SR_LINUX_RELEASE
# FROM ghcr.io/nokia/srlinux:$SR_LINUX_RELEASE
# FROM registry.srlinux.dev/pub/srlinux:$SR_LINUX_RELEASE

# Add Paris traceroute
# COPY --from=paris-traceroute /usr/local/bin/paris-* /usr/local/bin/
# COPY --from=paris-traceroute /usr/local/lib/* /usr/local/lib/

# Install balena, a modern Docker application to run containers within SRL
# Requires cSRL to be started using
# sudo docker run -it --privileged -v /tmp/var_lib_docker:/var/lib/balena-engine srl/auto-config:latest
# RUN curl -sfL https://balena.io/engine/install.sh | sh

# Integrate CLI agent, change CLI network namespace to 'default'
COPY cliplugin/*.py /opt/srlinux/python/virtual-env/lib/python3.6/site-packages/srlinux/mgmt/cli/plugins/reports/
RUN sudo sh -c ' echo "fabric = srlinux.mgmt.cli.plugins.reports.fabric:Plugin" >> /opt/srlinux/python/virtual-env/lib/python3.6/site-packages/srlinux-0.1-py3.6.egg-info/entry_points.txt'
# RUN sudo sed -i 's|/opt/srlinux/bin/sr_cli|/usr/sbin/ip netns exec srbase-mgmt /opt/srlinux/bin/sr_cli|g' /opt/srlinux/bin/ssh_sr_cli

# Add Dublin trace-route
#RUN sudo curl -4sL https://copr.fedorainfracloud.org/coprs/teknoraver/networking/repo/epel-7/teknoraver-networking-epel-7.repo -o /etc/yum.repos.d/teknoraver-networking-epel-7.repo && \
#    sudo yum install -y epel-release && \
#    sudo yum install -y dublin-traceroute

RUN sudo mkdir -p /etc/opt/srlinux/appmgr/ /opt/srlinux/agents/
COPY --chown=srlinux:srlinux ./docter-agent.yml /etc/opt/srlinux/appmgr
COPY ./src /opt/srlinux/agents/

# run pylint to catch any obvious errors
RUN PYTHONPATH=$AGENT_PYTHONPATH pylint --load-plugins=pylint_protobuf -E /opt/srlinux/agents/docter-agent

# Using a build arg to set the release tag, set a default for running docker build manually
ARG SRL_AUTO_CONFIG_RELEASE="[custom build]"
ENV SRL_AUTO_CONFIG_RELEASE=$SRL_AUTO_CONFIG_RELEASE
