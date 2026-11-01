from plate_reference import sample,run_cases

# Reference sample positions use integer multiplication/division, independent
# from the RTL accumulators. Unsampled pixels contain deliberately wrong data.
run_cases([('larger_plate',sample('AUY359'),6,128),
           ('larger_negative',sample('DMN112',negative=True),6,128)],
          'plate_larger',source_size=(832,320))
