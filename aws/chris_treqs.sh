#cp /workspace/.ssh/id_rsa_cmgeyer  /workspace/.ssh/id_rsa_cmgeyer.pub ~/.ssh
#ln -s ~/.ssh/id_rsa_cmgeyer ~/.ssh/id_rsa
#ln -s ~/.ssh/id_rsa_cmgeyer.pub ~/.ssh/id_rsa.pub
ssh-agent -k
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa
