// =============================================================================
//  Mule application CI/CD pipeline
// =============================================================================
//  Promotion model: a single build artifact is produced once and the SAME
//  artifact is promoted through dev -> test -> uat -> prod. Nothing is rebuilt
//  per environment; only the deployment profile and its properties change.
//
//  Required Jenkins configuration (see Jenkins-README.md):
//    * A `maven-settings` config file (Config File Provider plugin) holding
//      the Anypoint connected-app credentials and the encryption key.
//    * An agent labelled `mule-builder` with JDK 17 and Maven 3.8+.
//    * A `release-approvers` group for the production gate.
// =============================================================================

pipeline {
    agent { label 'mule-builder' }

    options {
        timeout(time: 60, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
        timestamps()
        ansiColor('xterm')
        skipDefaultCheckout(false)
    }

    tools {
        maven 'maven'
        jdk 'jdk-17'
    }

    parameters {
        choice(
            name: 'ENVIRONMENT',
            choices: ['dev', 'test', 'uat', 'prod'],
            description: 'Highest environment to promote to. Every lower environment is deployed first.'
        )
        booleanParam(
            name: 'SKIP_TESTS',
            defaultValue: false,
            description: 'Skip MUnit. Use only for an emergency hotfix, never for a normal release.'
        )
        booleanParam(
            name: 'ENFORCE_COVERAGE',
            defaultValue: true,
            description: 'Fail the build when MUnit coverage is below the threshold in pom.xml.'
        )
        booleanParam(
            name: 'PUBLISH_TO_EXCHANGE',
            defaultValue: false,
            description: 'Also publish the artifact to Anypoint Exchange.'
        )
    }

    environment {
        MAVEN_OPTS       = '-Xmx1024m -Djava.awt.headless=true'
        MAVEN_LOCAL_REPO = "${WORKSPACE}/.m2repository"
        // -B batch mode, -ntp no transfer progress: keeps the console log readable.
        MVN_FLAGS        = "-B -ntp -Dmaven.repo.local=${WORKSPACE}/.m2repository"
    }

    stages {

        stage('Build') {
            steps {
                script {
                    // Read once so every later stage names the same artifact.
                    env.APP_VERSION = readMavenPom().getVersion()
                    env.APP_NAME    = readMavenPom().getArtifactId()
                    currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.APP_NAME}:${env.APP_VERSION} -> ${params.ENVIRONMENT}"
                }
                withMavenSettings {
                    sh "mvn clean package ${MVN_FLAGS} -s \$MAVEN_SETTINGS -DskipMunitTests"
                }
            }
            post {
                success {
                    archiveArtifacts artifacts: 'target/*-mule-application.jar', fingerprint: true
                }
            }
        }

        stage('MUnit') {
            when { expression { !params.SKIP_TESTS } }
            steps {
                withMavenSettings {
                    // -DskipMunitTests is the MUnit switch; -DskipTests does NOT skip it.
                    sh """
                        mvn test ${MVN_FLAGS} -s \$MAVEN_SETTINGS \
                            -Dmunit.coverage.failBuild=${params.ENFORCE_COVERAGE}
                    """
                }
            }
            post {
                always {
                    junit testResults: 'target/surefire-reports/*.xml', allowEmptyResults: true
                    publishHTML(target: [
                        reportDir    : 'target/site/munit/coverage',
                        reportFiles  : 'summary.html',
                        reportName   : 'MUnit Coverage',
                        keepAll      : true,
                        allowMissing : true,
                        alwaysLinkToLastBuild: true
                    ])
                }
            }
        }

        stage('Publish to Exchange') {
            when { expression { params.PUBLISH_TO_EXCHANGE } }
            steps {
                withMavenSettings {
                    sh "mvn deploy ${MVN_FLAGS} -s \$MAVEN_SETTINGS -DskipMunitTests"
                }
            }
        }

        stage('Deploy to dev') {
            when { expression { envRank(params.ENVIRONMENT) >= envRank('dev') } }
            steps { deployTo('dev') }
        }

        stage('Smoke test dev') {
            when { expression { envRank(params.ENVIRONMENT) >= envRank('dev') } }
            steps { smokeTest('dev') }
        }

        stage('Deploy to test') {
            when { expression { envRank(params.ENVIRONMENT) >= envRank('test') } }
            steps { deployTo('test') }
        }

        stage('Smoke test test') {
            when { expression { envRank(params.ENVIRONMENT) >= envRank('test') } }
            steps { smokeTest('test') }
        }

        stage('Deploy to uat') {
            when { expression { envRank(params.ENVIRONMENT) >= envRank('uat') } }
            steps { deployTo('uat') }
        }

        stage('Smoke test uat') {
            when { expression { envRank(params.ENVIRONMENT) >= envRank('uat') } }
            steps { smokeTest('uat') }
        }

        stage('Approve production release') {
            when { expression { params.ENVIRONMENT == 'prod' } }
            steps {
                timeout(time: 24, unit: 'HOURS') {
                    input(
                        message  : "Deploy ${env.APP_NAME}:${env.APP_VERSION} to PRODUCTION?",
                        ok       : 'Approve',
                        submitter: 'release-approvers'
                    )
                }
            }
        }

        stage('Deploy to prod') {
            when { expression { params.ENVIRONMENT == 'prod' } }
            steps { deployTo('prod') }
        }

        stage('Smoke test prod') {
            when { expression { params.ENVIRONMENT == 'prod' } }
            steps { smokeTest('prod') }
        }
    }

    post {
        success {
            echo "SUCCESS: ${env.APP_NAME}:${env.APP_VERSION} promoted to ${params.ENVIRONMENT}"
            // slackSend channel: '#deployments', color: 'good',
            //           message: "Deployed ${env.APP_NAME}:${env.APP_VERSION} to ${params.ENVIRONMENT}"
        }
        failure {
            echo "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER} targeting ${params.ENVIRONMENT}"
            // slackSend channel: '#deployments', color: 'danger',
            //           message: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER} - ${env.BUILD_URL}"
            // emailext subject: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
            //          to: 'team@example.com', body: "Check: ${env.BUILD_URL}"
        }
        always {
            cleanWs(deleteDirs: true, notFailBuild: true)
        }
    }
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/** Promotion order. A target of `uat` implies dev and test are deployed first. */
int envRank(String environment) {
    return ['dev': 1, 'test': 2, 'uat': 3, 'prod': 4].get(environment, 0)
}

/** Wraps a block with the Anypoint credentials from the Config File Provider. */
def withMavenSettings(Closure body) {
    configFileProvider([configFile(fileId: 'maven-settings', variable: 'MAVEN_SETTINGS')]) {
        body()
    }
}

/**
 * Deploys the already-built artifact.
 *
 * `-DmuleDeploy` tells mule-maven-plugin to deploy rather than only publish,
 * and `-DskipMunitTests` keeps the deploy phase from re-running the suite.
 * The application name and sizing come from the profile in pom.xml, so there
 * is exactly one place to change them.
 */
def deployTo(String targetEnv) {
    withMavenSettings {
        retry(2) {
            sh """
                mvn deploy ${MVN_FLAGS} -s \$MAVEN_SETTINGS \
                    -P${targetEnv} -DmuleDeploy -DskipMunitTests
            """
        }
    }
    echo "Deployed ${env.APP_NAME}:${env.APP_VERSION} to ${targetEnv}"
}

/**
 * Hits /health-check on the deployed application and fails the stage if it is
 * not UP. A deploy that reports success but leaves the app unhealthy is the
 * failure mode this catches.
 *
 * Set APP_BASE_URL_<ENV> as a Jenkins global env var, e.g.
 *   APP_BASE_URL_DEV = https://my-app-dev.uk-e1.cloudhub.io/api
 */
def smokeTest(String targetEnv) {
    String baseUrl = env."APP_BASE_URL_${targetEnv.toUpperCase()}"
    if (!baseUrl) {
        echo "No APP_BASE_URL_${targetEnv.toUpperCase()} configured - skipping smoke test for ${targetEnv}."
        return
    }
    retry(3) {
        sh """
            set -e
            sleep 10
            STATUS=\$(curl -sS -o /tmp/health-${targetEnv}.json -w '%{http_code}' '${baseUrl}/health-check')
            echo "Health check returned HTTP \$STATUS"
            cat /tmp/health-${targetEnv}.json
            test "\$STATUS" = "200"
            grep -q '"status"[[:space:]]*:[[:space:]]*"UP"' /tmp/health-${targetEnv}.json
        """
    }
    echo "Smoke test passed for ${targetEnv}"
}
