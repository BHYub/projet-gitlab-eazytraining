



# CI/CD Pipeline for My Project

This file explains the CI/CD pipeline configuration for deploying a web application using GitLab CI/CD and Google Cloud Platform (GCP). Below, you'll find a detailed explanation of each stage and the important commands used.
## Requirements
To deploy on GCP I needed first to activate the **cloud run api and cloud build**
![Initial Image](/images/cloud%run)
## Overview

The CI/CD pipeline consists of the following stages:
1. **docker-build**: Build the Docker image.
2. **test-acc**: Test the Docker image.
3. **release**: Tag and push the Docker image to the registry.
4. **deploy_review**: Deploy the application to the review environment.
5. **stop_review**: Stop the review environment.
6. **deploy_staging**: Deploy the application to the staging environment.
7. **test_staging**: Test the application in the staging environment.
8. **deploy_prod**: Deploy the application to the production environment.
9. **test_prod**: Test the application in the production environment.

## Stages and Commands

### docker-build

This stage builds the Docker image for the web application.

```yaml
docker-build:
  image: docker:20.10.7
  stage: docker-build
  services:
    - name: docker:dind
      alias: docker
  script:
    - docker build --pull -t webapp .
    - docker save webapp > webapp.tar
  artifacts:
    untracked: false
    when: on_success
    access: all
    paths:
      - "webapp.tar"
    expire_in: 30 days
```

- **docker build --pull -t webapp .**: This command builds a Docker image with the tag `webapp`. The `--pull` option ensures that the latest version of the base image is pulled.
- **docker save webapp > webapp.tar**: This command saves the `webapp` image to a tar file named `webapp.tar` for later use.
- To communicate with the docker daemon we needed the service **docker:dind**

### test-acc

This stage tests the built Docker image by running it and verifying its content.

```yaml
test-acc:
  image: docker:cli
  stage: test-acc
  script:
    - docker load < webapp.tar
    - docker run -d -p 80:80 --name webapp webapp
    - apk add --no-cache --update curl
    - curl -s "http://docker:80" -o temp.html
    - grep -q "HTML5" temp.html
    - rm temp.html
```

- **docker load < webapp.tar**: This command loads the Docker image from the tar file `webapp.tar`.
- **docker run -d -p 80:80 --name webapp webapp**: This command runs the Docker container in detached mode (`-d`), mapping port 80 of the host to port 80 of the container, and names the container `webapp`.
- **apk add --no-cache --update curl**: This command installs the `curl` command-line tool in the Alpine Linux environment.
- **curl -s "http://docker:80" -o temp.html**: This command fetches the homepage of the application running in the container and saves it to `temp.html`, you can tell me why save it tho , I mean yeah i could have just ran a curl command and pipe it to grep -q command but the result of the curl is way too heavy to do so and it results to an error so i had to go this way.
- **grep -q "HTML5" temp.html**: This command checks if the fetched page contains the string "HTML5".
- **rm temp.html**: This command removes the `temp.html` file.
- In this part we also needed the **docker:dind** but we had by declaring it as global to the file.
### release

This stage tags and pushes the Docker image to the Docker registry.

```yaml
release image:
  stage: release
  image: docker:20.10.7
  script:
    - docker load < webapp.tar
    - docker tag webapp "${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}"
    - docker tag webapp "${IMAGE_NAME}:${CI_COMMIT_REF_NAME}"
    - docker login -u "$CI_REGISTRY_USER" -p "$CI_REGISTRY_PASSWORD" $CI_REGISTRY
    - docker push "${IMAGE_NAME}:${CI_COMMIT_REF_NAME}"
    - docker push "${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}"
```

- **docker load < webapp.tar**: Loads the Docker image from the tar file `webapp.tar`.
- **docker tag webapp "${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}"**: Tags the Docker image with the commit SHA.
- **docker tag webapp "${IMAGE_NAME}:${CI_COMMIT_REF_NAME}"**: Tags the Docker image with the branch name.
- **docker login -u "$CI_REGISTRY_USER" -p "$CI_REGISTRY_PASSWORD" $CI_REGISTRY**: Logs into the Docker registry using credentials stored in environment variables.
- **docker push "${IMAGE_NAME}:${CI_COMMIT_REF_NAME}"**: Pushes the Docker image tagged with the branch name to the registry.
- **docker push "${IMAGE_NAME}:${CI_COMMIT_SHORT_SHA}"**: Pushes the Docker image tagged with the commit SHA to the registry.

### deploy_review

This stage deploys the application to the review environment on GCP.

```yaml
deploy_review:
  stage: deploy_review
  image: google/cloud-sdk:slim
  only:
    - merge_requests
  script:
    - echo $GCLOUD_SERVICE_KEY > /tmp/gcloud-service-key.json
    - gcloud auth activate-service-account --key-file=/tmp/gcloud-service-key.json
    - gcloud config set project $PROJECT_ID
    - gcloud builds submit --config=cloudbuild_review.yaml --suppress-logs --substitutions _IMAGE_NAME=$IMAGE_NAME,_CI_COMMIT_SHORT_SHA=$CI_COMMIT_SHORT_SHA,_PROJECT_ID=$PROJECT_ID || true
    - |
      export SERVICE_URL_REVIEW=$(gcloud run services describe mon-service-review --region $REGION --format='value(status.url)')
      echo "SERVICE_URL_REVIEW=$SERVICE_URL_REVIEW" >> deploy.env
  artifacts:
    reports:
      dotenv: deploy.env
  environment:
    name: REVIEW/$CI_COMMIT_SHORT_SHA
    url: $SERVICE_URL_REVIEW
    on_stop: stop_review
```
- I used a **google/cloud-sdk:slim** image to execute my commands and when the script finishes I catch the url and put it in  **deploy.env** so I can report it and use it in the environment .
- The environement **stop** button with action a different stage that will delete the service in **GCP** in addition of deleting it on gitlab , we will see that later.


**Script**:

- **echo $GCLOUD_SERVICE_KEY > /tmp/gcloud-service-key.json**: Writes the GCP service key to a temporary file.
- **gcloud auth activate-service-account --key-file=/tmp/gcloud-service-key.json**: Authenticates with GCP using the service account key.
- **gcloud config set project $PROJECT_ID**: Sets the current GCP project.
- **gcloud builds submit --config=cloudbuild_review.yaml --suppress-logs --substitutions _IMAGE_NAME=$IMAGE_NAME,_CI_COMMIT_SHORT_SHA=$CI_COMMIT_SHORT_SHA,_PROJECT_ID=$PROJECT_ID**: Submits a build to Google Cloud Build with specific substitutions.

- **export SERVICE_URL_REVIEW=$(gcloud run services describe mon-service-review --region $REGION --format='value(status.url)')**: Retrieves the URL of the deployed service.
- **echo "SERVICE_URL_REVIEW=$SERVICE_URL_REVIEW" >> deploy.env**: Saves the service URL to an environment file.

### cloudbuild.yaml Explanation

 For the matter of building on GCP I had to create some cloudbuild files , here is the **cloudbuild_review explanations** :

 ```yaml
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args: ['pull', '$_IMAGE_NAME:$_CI_COMMIT_SHORT_SHA']
  - name: 'gcr.io/cloud-builders/docker'
    args: ['tag', '$_IMAGE_NAME:$_CI_COMMIT_SHORT_SHA', 'gcr.io/$_PROJECT_ID/$_IMAGE_NAME:$_CI_COMMIT_SHORT_SHA']
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'gcr.io/$_PROJECT_ID/$_IMAGE_NAME:$_CI_COMMIT_SHORT_SHA']
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    entrypoint: 'gcloud'
    args: ['run', 'deploy', 'mon-service-review', '--image', 'gcr.io/$_PROJECT_ID/$_IMAGE_NAME:$_CI_COMMIT_SHORT_SHA', '--region', 'us-west2', '--platform', 'managed', '--port', '80', '--quiet', '--allow-unauthenticated']
```
- **gcr.io/cloud-builders/docker**: This specifies the Docker builder image provided by Google Cloud.
- **args: ['pull', '$_IMAGE_NAME:$_CI_COMMIT_SHORT_SHA']**: This command pulls the Docker image with the tag corresponding to the commit SHA from the registry.
- **args: ['tag', '$_IMAGE_NAME:$_CI_COMMIT_SHORT_SHA', 'gcr.io/$_PROJECT_ID/$_IMAGE_NAME:$_CI_COMMIT_SHORT_SHA']**: This command tags the pulled Docker image with the GCP project ID and commit SHA.
- **args: ['push', 'gcr.io/$_PROJECT_ID/$_IMAGE_NAME:$_CI_COMMIT_SHORT_SHA']**: This command pushes the tagged Docker image to the Google Container Registry within the specified project.
- **entrypoint: 'gcloud'**: This sets the entry point to gcloud, the Google Cloud CLI tool.
- **args: ['run', 'deploy', 'mon-service-review', '--image', 'gcr.io/$_PROJECT_ID/$_IMAGE_NAME:$_CI_COMMIT_SHORT_SHA', '--region', 'us-west2', '--platform', 'managed', '--port', '80', '--quiet', '--allow-unauthenticated']**: This command deploys the Docker image to Google Cloud Run. The service is named mon-service-review, deployed to the us-west2 region, listens on port 80, and allows unauthenticated access.

### stop_review

This stage stops the review environment and will be trigered manually from the stop button of the review environment.
 
It's only on merge requests like the review stage .

```yaml
stop_review:
  stage: stop_review
  variables:
    GIT_STRATEGY: none
  environment:
    name: REVIEW/$CI_COMMIT_SHORT_SHA
    action: stop
  only:
    - merge_requests
  script:
    - echo $GCLOUD_SERVICE_KEY > /tmp/gcloud-service-key.json
    - gcloud auth activate-service-account --key-file=/tmp/gcloud-service-key.json
    - gcloud config set project $PROJECT_ID
    - gcloud run services delete mon-service-review --region $REGION --quiet || true
  when: manual
  allow_failure: true
```

- **gcloud run services delete mon-service-review --region $REGION --quiet**: Deletes the review environment service.

### deploy_staging

This stage deploys the application to the staging environment on GCP.
Pretty much the same as the **deploy_review** exept for the condition branch it's on main only not on merge requests .
And in this stage i decided not to add a stop for the evironment , we've already seen that.

```yaml
deploy_staging:
  stage: deploy_staging
  image: google/cloud-sdk:slim
  only:
    - main
  script:
    - echo $GCLOUD_SERVICE_KEY > /tmp/gcloud-service-key.json
    - gcloud auth activate-service-account --key-file=/tmp/gcloud-service-key.json
    - gcloud config set project $PROJECT_ID
    - gcloud builds submit --config=cloudbuild_staging.yaml --suppress-logs --substitutions _IMAGE_NAME=$IMAGE_NAME,_CI_COMMIT_SHORT_SHA=$CI_COMMIT_SHORT_SHA,_PROJECT_ID=$PROJECT_ID || true
    - |
      export SERVICE_URL_STAGING=$(gcloud run services describe mon-service-staging --region $REGION --format='value(status.url)')
      echo "SERVICE_URL_STAGING=$SERVICE_URL_STAGING" >> deploy.env
  artifacts:
    reports:
      dotenv: deploy.env
  environment:
    name: STAGING/$CI_COMMIT_SHORT_SHA
    url: $SERVICE_URL_STAGING
```

### test_staging

This stage tests the application in the staging environment.

```yaml
test_staging:
  stage: test_staging
  image: alpine
  script:
    - apk add --no-cache --update curl
    - curl -s "$DOMAIN" -o temp.html
    - grep -q "Dimension" temp.html
    - rm temp.html
  variables:
    DOMAIN: $SERVICE_URL_STAGING
```
The same as the **acceptance test** but here we do it on deployed environment

### deploy_prod and test_prod 

These two are the same as for staging  nothing more , we  just changed the name and the service where we deploy .

### anchors 
I did some **anchors** to not repeat the same code every time : 
```yaml
.gcp_login: &gcp_login
   - echo $GCLOUD_SERVICE_KEY  > /tmp/gcloud-service-key.json
   - gcloud auth activate-service-account --key-file=/tmp/gcloud-service-key.json
   - gcloud config set project $PROJECT_ID   
.app_test: &app_test
   - apk add --no-cache  --update curl
   - curl -s "$DOMAIN" -o temp.html
   - grep -q "Dimension" temp.html
   - rm temp.html

```
So I have here for the **GCP login** and the **app test** in the deployed envs some anchors that I integrated in the code like this :
 ```yaml
deploy_prod:
  stage: deploy_prod
  image: google/cloud-sdk:slim
  
  script:
   - *gcp_login
   - gcloud builds submit  --config=cloudbuild_prod.yaml --suppress-logs --substitutions _IMAGE_NAME=$IMAGE_NAME,_CI_COMMIT_SHORT_SHA=$CI_COMMIT_SHORT_SHA,_PROJECT_ID=$PROJECT_ID || true
   - |
      export SERVICE_URL_PROD=$(gcloud run services describe mon-service-prod --region $REGION --format='value(status.url)')
      echo "SERVICE_URL_PROD=$SERVICE_URL_PROD" >> deploy.env
  artifacts:
    reports:
      dotenv: deploy.env     
  environment:
    name: PROD/$CI_COMMIT_SHORT_SHA
    url: $SERVICE_URL_PROD 


test_prod:
  stage: test_prod
  image: alpine
  script:
   - *app_test
  variables:
    DOMAIN: $SERVICE_URL_PROD 


```
On all deployements .

### Running the pipeline 

