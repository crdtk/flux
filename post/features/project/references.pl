%% project/references — hardware reference PDFs CLAUDE.md tells every
%% session to consult (the SN8100 datasheet has no stable public URL —
%% excluded).

reference_pdf('References/Motherboard/E3C256D4I-2T.pdf',
    'https://download.asrock.com/Manual/E3C256D4I-2T.pdf').
reference_pdf('References/Motherboard/ASUS-Prime-X299-A-II.pdf',
    'https://dlcdnets.asus.com/pub/ASUS/mb/LGA2066/PRIME_X299-A_II/E15936_PRIME_X299-A_II_UM_V2_WEB.pdf').
reference_pdf('References/Case/ENTHOO-PRO-II/Enthoo_Pro2_Manual_v1.1.pdf',
    'https://phanteks.com/manuals/Enthoo_Pro2_Manual_v1.1.pdf').
reference_pdf('References/Storage/MB111VP-B/MB111VP_B_Manual.pdf',
    'https://global.icydock.com/vancheerfile/files/installation_guide/MB111VP_B_Manual.pdf').
reference_pdf('References/Storage/MB705M2P-B/MB705M2P-B_Manual.pdf',
    'https://www.icydock.com/Installation%20Guide/MB705M2P-B-webpage_manual.pdf').
user_config(reference_pdf(Rel), Check, Fix) :-
    reference_pdf(Rel, URL),
    project_dir(Proj),
    format(atom(Check), "test -s '~w/~w'", [Proj, Rel]),
    format(atom(Fix),
        "mkdir -p \"$(dirname '~w/~w')\" && curl -fL -o '~w/~w' '~w'",
        [Proj, Rel, Proj, Rel, URL]).

user_config_deps(reference_pdf(_), [internet_ok]).
