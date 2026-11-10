import {
  Button,
  LabeledList,
  ProgressBar,
  Section,
} from 'tgui-core/components';
import { toFixed } from 'tgui-core/math';
import type { BooleanLike } from 'tgui-core/react';

import { useBackend } from '../backend';
import { Window } from '../layouts';

type Data = {
  doorstatus: BooleanLike;
  stored: number;
  max: number;
  // Babylon generation interlock only; absent on the upstream controller.
  generation?: number;
  required?: number;
  battery?: number;
};

export const VaultController = (props) => {
  const { act, data } = useBackend<Data>();
  const { doorstatus, stored, max, generation } = data;
  const isGenerationInterlock = generation !== undefined;

  return (
    <Window width={340} height={isGenerationInterlock ? 190 : 120}>
      <Window.Content>
        <Section
          title="Lock Status: "
          buttons={
            <Button
              content={doorstatus ? 'Locked' : 'Unlocked'}
              icon={doorstatus ? 'lock' : 'unlock'}
              disabled={stored < max}
              onClick={() => act('togglelock')}
            />
          }
        >
          {isGenerationInterlock ? <GenerationList /> : <VaultList />}
        </Section>
      </Window.Content>
    </Window>
  );
};

/** Upstream derelict controller: charge siphoned from the cable. */
const VaultList = (props) => {
  const { data } = useBackend<Data>();
  const { stored, max } = data;

  return (
    <LabeledList>
      <LabeledList.Item label="Charge">
        <ProgressBar
          value={stored / max}
          ranges={{
            good: [1, Infinity],
            average: [0.3, 1],
            bad: [-Infinity, 0.3],
          }}
        >
          {`${toFixed(stored / 1000)} / ${toFixed(max / 1000)} kW`}
        </ProgressBar>
      </LabeledList.Item>
    </LabeledList>
  );
};

const formatPower = (watts: number) => {
  if (watts >= 1e6) {
    return `${toFixed(watts / 1e6, 2)} MW`;
  }
  return `${toFixed(watts / 1e3)} kW`;
};

/** Babylon interlock: live generation on the cable, held for a short time. */
const GenerationList = (props) => {
  const { data } = useBackend<Data>();
  const { stored, max, generation = 0, required = 1, battery = 0 } = data;

  return (
    <LabeledList>
      <LabeledList.Item label="Live generation">
        <ProgressBar
          value={generation / required}
          ranges={{
            good: [1, Infinity],
            average: [0.5, 1],
            bad: [-Infinity, 0.5],
          }}
        >
          {`${formatPower(generation)} / ${formatPower(required)}`}
        </ProgressBar>
      </LabeledList.Item>
      <LabeledList.Item label="Battery output" color={battery > 0 ? 'bad' : 'label'}>
        {battery > 0 ? `${formatPower(battery)} ignored` : 'none'}
      </LabeledList.Item>
      <LabeledList.Item label="Hold">
        <ProgressBar
          value={max > 0 ? stored / max : 0}
          ranges={{
            good: [1, Infinity],
            average: [0.01, 1],
            bad: [-Infinity, 0.01],
          }}
        >
          {stored >= max
            ? 'stable'
            : `${toFixed(stored / 10)} / ${toFixed(max / 10)} s`}
        </ProgressBar>
      </LabeledList.Item>
    </LabeledList>
  );
};
