# License and compliance notes

This document explains the intended public-use boundary of the MedicineApp ISBM
2026 research artifact. It is general project guidance, not legal, regulatory,
or medical advice.

## 1. Source-code license

The repository includes an [MIT License](../LICENSE). The MIT license permits
use, copying, modification, merging, publication, distribution, sublicensing,
and sale of copies of the covered software, provided that the copyright and
permission notices are retained. The software is provided without warranty.

No government registration, paid application, or online license activation is
required to apply or use the MIT license. GitHub recommends placing a detectable
license file in the repository so that users know what they may do with the
code. Copyright protection is generally automatic under the Berne Convention;
voluntary national registration is separate and may be useful as evidence of
authorship or ownership.

References:

- [GitHub: Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
- [Open Source Initiative: MIT License](https://opensource.org/license/MIT)
- [WIPO: Copyright and registration](https://www.wipo.int/en/web/copyright/)

## 2. What the MIT license does not automatically cover

The repository license applies only to material for which the listed copyright
holders have the authority to grant that license. It does not override the
rights or terms attached to:

- prescription photographs, OCR observations, annotations, or patient data;
- VAIPE or other third-party datasets;
- a provider-controlled Vietnamese drug catalogue;
- PhoBERT or other pretrained/fine-tuned model files;
- Google ML Kit, OpenFDA, external APIs, or hosted services;
- third-party Flutter, Python, Node.js, Android, and native dependencies; or
- files available through the supplementary Google Drive folder.

Before redistributing any such resource, preserve its original license and
notice, confirm that redistribution is allowed, and document its provenance.
Access to a file is not equivalent to permission to republish it.

The MIT license is a copyright license and does not grant a separate trademark
right in the MedicineApp or MekongLab names or logos. Branding reuse must not
imply endorsement. Registering a software copyright or a trademark, if desired,
is separate from selecting the MIT license.

## 3. Research and medical-use boundary

MedicineApp is a research prototype and is not represented as a certified
medical device. It must not independently diagnose, prescribe, dispense, or
recommend a dose. A qualified human must verify OCR and medication information
before any downstream use.

Deployment in clinical, pharmacy, or patient-care settings requires a separate
assessment of medical-device classification, clinical validation, risk
management, usability, cybersecurity, post-market obligations, and local law.
The public paper evaluation is not a substitute for that assessment.

## 4. Personal data and research records

Real prescriptions can contain names, identifiers, diagnoses, medication
history, provider details, and other sensitive information. Users processing
such material must establish a lawful basis, appropriate consent or research
approval, access controls, retention/deletion rules, and incident procedures.

Vietnam's [Law on Personal Data Protection No. 91/2025/QH15](https://vanban.chinhphu.vn/?classid=1&docid=214590&pageid=27160&typegroup=)
was issued on 26 June 2025 and took effect on 1 January 2026. Users remain
responsible for determining which provisions and any other applicable laws,
institutional policies, ethics approvals, or contractual restrictions apply to
their processing.

Never place identifiable prescription material in:

- a public Git repository or fork;
- public GitHub issues, pull requests, CI logs, or release artifacts;
- a public/shared Drive folder without an approved data-sharing basis;
- screenshots, demos, test fixtures, telemetry, or crash reports; or
- shell history and copied terminal output.

## 5. Minimum release checklist

Before publishing a new code, data, or model artifact:

1. identify the author/owner and redistribution license;
2. check for personal data, secrets, credentials, and capture identifiers;
3. document consent, institutional approval, and third-party restrictions;
4. record version, filename, size, and SHA-256 checksum;
5. separate public source from controlled-access data/model resources;
6. run `./reproduce.sh` and the relevant application tests;
7. state whether the artifact supports aggregate verification or full
   re-execution; and
8. obtain specialist legal/regulatory review before clinical deployment.

## 6. No compliance certification

The presence of this document, a license, tests, encryption, or de-identification
does not certify compliance with privacy, research, cybersecurity, or
medical-device rules. Compliance depends on the data, users, deployment,
jurisdiction, agreements, and operational controls in each use case.
