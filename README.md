# Symfony Security Updater

## Usage 

1. Fill the ``repositories`` array in the ``security.sh`` with ssh uri (eg. ``git@gitlab.com:MyName/my-repo.git``) 
2. Add the ``GITLAB_PRIVATE_TOKEN`` env var to your terminal with a valid gitlab private token
3. Run the script ``security.sh``. The script will write which project has a CVE, 
   it will update the composer.lock and create a Merge Request on the repository targeting the branch develop
