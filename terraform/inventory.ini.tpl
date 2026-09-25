[ubuntu]
%{ for name, ip in nodes ~}
${name} ansible_host=${ip}
%{endfor ~}

[ubuntu:vars]
ansible_user=ansible
ansible_ssh_private_key_file=${ssh_private_key_path}
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=yes -o UserKnownHostsFile="${known_hosts_path}"'
